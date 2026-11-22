#!/usr/bin/env python3
"""Manifest validation and project-bound startup audit state (Python 3.11+)."""
from contextlib import contextmanager
import datetime as dt
import fnmatch
import hashlib
import json
import os
from pathlib import Path
import re
import secrets
import shlex
import shutil
import subprocess
import sys
import tempfile
import time
import tomllib
import xml.etree.ElementTree as ET

from path_helpers import relative_key, resolve_path

UNPINNED = "__version_sentinel_unpinned__"
EXCLUDED = {".git", ".worktrees", "node_modules", "target", ".venv", "venv", ".version-sentinel", "__pycache__"}
LOCKFILES = {"package-lock.json", "npm-shrinkwrap.json", "pnpm-lock.yaml", "yarn.lock", "bun.lock", "bun.lockb", "poetry.lock", "uv.lock", "Cargo.lock", "packages.lock.json", "Directory.Packages.props"}


def fail(message):
    raise ValueError(message)


def ecosystem(path):
    name = Path(path).name
    if name == "package.json":
        return "npm"
    if fnmatch.fnmatch(name, "requirements*.txt") or fnmatch.fnmatch(name, "constraints*.txt"):
        return "pip"
    if name == "pyproject.toml":
        return "pyproject"
    if name == "Cargo.toml":
        return "cargo"
    if name.endswith((".csproj", ".fsproj", ".vbproj")):
        return "csproj"
    return ""


def mapping(value, label):
    if not isinstance(value, dict):
        fail(f"{label} must be a table/object")
    return value



def reject_resolver_sections(data, names, label):
    for name in names:
        if name in data and mapping(data[name], f"{label}.{name}"):
            fail(f"Unsupported dependency-selector construct: {label}.{name}. Resolver overrides/catalogues are not fully tracked; dependency work is blocked.")


def strings(value, label):
    if not isinstance(value, list) or not all(isinstance(v, str) for v in value):
        fail(f"{label} must be an array of strings")
    return value


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            fail(f"duplicate JSON key {key}")
        result[key] = value
    return result


def external(raw):
    return raw.startswith(("file:", "git+", "git:", "git@", "github:", "gitlab:", "bitbucket:", "workspace:", "link:", "portal:", "http://", "https://", "ssh://", "./", "../", "/"))


def version(raw, npm=False):
    if not isinstance(raw, str):
        fail("dependency version must be a string")
    raw = raw.strip()
    if external(raw):
        return None
    if not raw or raw in {"latest", "next", "*"} or "*" in raw:
        return UNPINNED
    if npm and (re.search(r"(^|\.)(x|X)(\.|$)", raw) or re.search(r"\s|\|", raw)):
        return UNPINNED
    result = re.sub(r"^[v^~<>=! ]+", "", raw)
    # Existing Python constraints are audited using their first declared bound.
    result = result.split(",", 1)[0]
    if not re.fullmatch(r"[0-9][A-Za-z0-9.+_!-]*", result):
        return UNPINNED
    if npm and not re.match(r"^\d+\.\d+\.\d+", result):
        return UNPINNED
    return result


def pep508(spec):
    if not isinstance(spec, str):
        fail("Python dependency must be a string")
    spec = spec.split(";", 1)[0].strip()
    match = re.fullmatch(r"([A-Za-z0-9][A-Za-z0-9._-]*)(?:\[[^\]]*\])?\s*(.*)", spec)
    if not match:
        fail(f"unrecognized Python dependency: {spec}")
    name, raw = match.groups()
    if raw.startswith("@"):
        if not raw[1:].strip():
            fail(f"missing direct reference for {name}")
        return None
    # PEP 508 permits one optional pair around an otherwise identical list.
    if raw.startswith("(") and raw.endswith(")"):
        raw = raw[1:-1].strip()
        if not raw:
            fail(f"unrecognized Python version selector for {name}")
    if raw and not re.fullmatch(r"(?:===|==|~=|>=|<=|>|<|!=|\^|~)\s*[A-Za-z0-9][A-Za-z0-9.*+_!-]*(?:\s*,\s*(?:===|==|~=|>=|<=|>|<|!=)\s*[A-Za-z0-9][A-Za-z0-9.*+_!-]*)*", raw):
        fail(f"unrecognized Python version selector for {name}")
    return name, version(raw)



def requirements_lines(content):
    # Match pip's line-continuation syntax in both extraction and discovery.
    return content.replace("\\\r\n", "").replace("\\\n", "").splitlines()


def requirements_option_line(line):
    """Accept complete supported option lines, never an unchecked token suffix."""
    if not line.startswith("-"):
        return False
    values = {
        "--index-url", "--extra-index-url", "--trusted-host", "--find-links",
        "--no-binary", "--only-binary", "--use-feature", "--editable",
        "-i", "-f", "-e",
    }
    switches = {
        "--no-index", "--pre", "--prefer-binary", "--require-hashes",
        "--no-require-hashes", "--all-releases", "--only-final",
    }
    lexer = shlex.shlex(line, posix=True)
    lexer.whitespace_split = True
    lexer.commenters = ""
    # Requirements paths can contain Windows separators on every host.
    lexer.escape = ""
    tokens = list(lexer)
    index = 0
    while index < len(tokens):
        token = tokens[index]
        index += 1
        name, separator, argument = token.partition("=")
        if token.startswith(("-i", "-f", "-e")) and not token.startswith("--"):
            name, argument = token[:2], token[2:]
            separator = bool(argument)
        if name in switches:
            if separator:
                fail(f"unexpected value for requirements option {name}")
            continue
        if name not in values:
            fail(f"unsupported requirements option or trailing dependency: {token}")
        if not separator:
            if index >= len(tokens) or tokens[index].startswith("-"):
                fail(f"missing value for requirements option {name}")
            argument = tokens[index]
            index += 1
        if not argument:
            fail(f"missing value for requirements option {name}")
        if name in {"--editable", "-e"} and not (
            external(argument) or argument in {".", ".."}
            or re.match(r"^[A-Za-z]:[\\/]", argument) or Path(argument).is_dir()
        ):
            fail("unsupported editable dependency; use an explicit local/VCS source")
    return True


def xml_dependency_shape(node):
    """Ignore XML layout while keeping dependency attributes and child values."""
    def meaningful(value):
        return value if value and value.strip() else None
    return {
        "tag": node.tag,
        "attributes": dict(sorted(node.attrib.items())),
        "text": meaningful(node.text),
        "tail": meaningful(node.tail),
        "children": [xml_dependency_shape(child) for child in node],
    }


def dependencies(path, content, intents=False):
    """Validate supported schema and emit registry package / declared bound pairs."""
    eco = ecosystem(path)
    result = []
    occurrences = {}

    def emit(package, selected, selector, location):
        if intents:
            key = (package, location)
            position = occurrences.get(key, 0)
            occurrences[key] = position + 1
            intent = json.dumps({"location": location, "occurrence": position, "selector": selector}, sort_keys=True, separators=(",", ":"))
            result.append((package, selected, intent))
        else:
            result.append((package, selected))

    if eco == "npm":
        data = mapping(json.loads(content, object_pairs_hook=unique_object), "package.json")
        reject_resolver_sections(data, ("resolutions", "catalog", "catalogs", "packageExtensions"), "npm")
        pnpm = mapping(data.get("pnpm", {}), "pnpm")
        reject_resolver_sections(pnpm, ("catalog", "catalogs", "packageExtensions"), "pnpm")
        for section in ("dependencies", "devDependencies", "peerDependencies", "optionalDependencies"):
            for name, raw in mapping(data.get(section, {}), section).items():
                if not isinstance(raw, str) or not name or any(c.isspace() for c in name):
                    fail(f"invalid {section} entry {name}")
                declaration, selector = name, raw
                if raw.startswith("npm:"):
                    match = re.fullmatch(r"(@[^/@]+/[^@]+|[^/@]+)(?:@(.+))?", raw[4:])
                    if not match:
                        fail(f"unsupported npm alias {raw}")
                    name, raw = match.group(1), match.group(2) or ""
                selected = version(raw, npm=True)
                if selected is not None:
                    emit(name, selected, selector, f"{section}.{declaration}")
        # Keep override keys in the location so version-qualified rules remain
        # distinct even when they resolve to the same registry package/version.
        def package_overrides(table, location, qualified=False):
            name_pattern = r"((?:@[A-Za-z0-9._~-]+/)?[A-Za-z0-9_~-][A-Za-z0-9._~-]*)"
            if qualified:
                name_pattern += r"(?:@([^@/\n]+))?"
            for name, raw in mapping(table, location).items():
                target = re.fullmatch(name_pattern, name)
                if (not target or not isinstance(raw, str)
                        or (qualified and target.group(2) is not None and not target.group(2).strip())
                        or (location == "pnpm.overrides" and raw == "-")):
                    fail(f"Unsupported dependency-selector construct: {location}.{name}. Only flat package keys with string replacements are tracked; npm keys may include version selectors. Nested, parent, and deletion forms remain blocked.")
                package = target.group(1)
                selector = {"override": raw}
                if raw.startswith("$"):
                    reference = raw[1:]
                    pnpm_reference = location == "pnpm.overrides"
                    if pnpm_reference:
                        # PNPM merges dev, runtime, then optional declarations;
                        # peer dependencies do not supply version references.
                        sections = ("optionalDependencies", "dependencies", "devDependencies")
                    else:
                        sections = ("devDependencies", "optionalDependencies", "dependencies", "peerDependencies")
                    for section in sections:
                        available = data.get(section, {})
                        resolved = available.get(reference)
                        if resolved or (pnpm_reference and reference in available):
                            break
                    else:
                        resolved = None
                    if not resolved:
                        fail(f"Unsupported dependency-selector reference: {location}.{name} cannot resolve {raw} to a direct dependency.")
                    selector.update(reference=reference, source=section, resolved=resolved)
                    raw = resolved
                if raw.startswith("npm:"):
                    match = re.fullmatch(r"(@[^/@]+/[^@]+|[^/@]+)(?:@(.+))?", raw[4:])
                    if not match:
                        fail(f"unsupported npm alias {raw}")
                    package, raw = match.group(1), match.group(2) or ""
                selected = version(raw, npm=True)
                if selected is not None:
                    emit(package, selected, selector, f"{location}.{name}")

        package_overrides(data.get("overrides", {}), "overrides", qualified=True)
        package_overrides(pnpm.get("overrides", {}), "pnpm.overrides")
    elif eco == "pip":
        # Continuations and hashes are normal pip syntax. Includes are checked
        # against project inventory separately, never fetched or reconstructed.
        for line in requirements_lines(content):
            line = line.split("#", 1)[0].strip()
            if not line:
                continue
            if line.startswith(("-r", "--requirement", "-c", "--constraint")):
                if not re.fullmatch(r"(?:-[rc]\s*|--(?:requirement|constraint)(?:\s+|=))[^\s]+", line):
                    fail("unsupported requirements include")
                continue
            if requirements_option_line(line) or external(line):
                continue
            line = re.sub(r"\s+--hash=[^\s]+", "", line)
            parsed = pep508(line)
            if parsed:
                emit(*parsed, line, "requirements")
    elif eco in {"pyproject", "cargo"}:
        data = tomllib.loads(content)
        if eco == "cargo":
            reject_resolver_sections(data, ("patch", "replace"), "Cargo")
            def cargo_table(table, location):
                for name, spec in mapping(table, "Cargo dependencies").items():
                    declaration = name
                    if isinstance(spec, dict):
                        if "path" in spec or "git" in spec or spec.get("workspace") is True:
                            continue
                        name = spec.get("package", name)
                        raw = spec.get("version", "")
                    elif isinstance(spec, str):
                        raw = spec
                    else:
                        fail(f"unsupported Cargo dependency {name}")
                    if not isinstance(name, str):
                        fail("Cargo package name must be a string")
                    selected = version(raw)
                    if selected is not None:
                        emit(name, selected, spec, f"{location}.{declaration}")

            def cargo_sections(section, location):
                section = mapping(section, "Cargo section")
                for key in ("dependencies", "dev-dependencies", "build-dependencies"):
                    cargo_table(section.get(key, {}), f"{location}.{key}")

            cargo_sections(data, "cargo")
            cargo_sections(data.get("workspace", {}), "workspace")
            for target_name, target in mapping(data.get("target", {}), "Cargo target").items():
                cargo_sections(target, f"target.{target_name}")
        else:
            build_system = mapping(data.get("build-system", {}), "build-system")
            for spec in strings(build_system.get("requires", []), "build-system.requires"):
                parsed = pep508(spec)
                if parsed:
                    emit(*parsed, spec, "build-system.requires")
            project = mapping(data.get("project", {}), "project")
            dynamic = strings(project.get("dynamic", []), "project.dynamic")
            if {"dependencies", "optional-dependencies"}.intersection(dynamic):
                fail("dynamic Python dependencies cannot be audited safely")
            for spec in strings(project.get("dependencies", []), "project.dependencies"):
                parsed = pep508(spec)
                if parsed:
                    emit(*parsed, spec, "project.dependencies")
            for group_name, group in mapping(project.get("optional-dependencies", {}), "project.optional-dependencies").items():
                for spec in strings(group, "optional dependency group"):
                    parsed = pep508(spec)
                    if parsed:
                        emit(*parsed, spec, f"project.optional-dependencies.{group_name}")
            tool = mapping(data.get("tool", {}), "tool")
            poetry = mapping(tool.get("poetry", {}), "tool.poetry")

            def poetry_table(table, location):
                for name, spec in mapping(table, "Poetry dependencies").items():
                    if name == "python":
                        continue
                    if isinstance(spec, list):
                        if not spec or not all(isinstance(item, dict) for item in spec):
                            fail(f"unsupported Poetry dependency {name}: expected a nonempty array of tables")
                        specs = spec
                    else:
                        specs = [spec]
                    for item in specs:
                        if isinstance(item, dict):
                            if any(k in item for k in ("path", "git", "url")):
                                continue
                            raw = item.get("version", "")
                        elif isinstance(item, str):
                            raw = item
                        else:
                            fail(f"unsupported Poetry dependency {name}")
                        selected = version(raw)
                        if selected is not None:
                            emit(name, selected, item, f"{location}.{name}")

            poetry_table(poetry.get("dependencies", {}), "tool.poetry.dependencies")
            poetry_table(poetry.get("dev-dependencies", {}), "tool.poetry.dev-dependencies")
            for group_name, group in mapping(poetry.get("group", {}), "Poetry groups").items():
                poetry_table(mapping(group, "Poetry group").get("dependencies", {}), f"tool.poetry.group.{group_name}.dependencies")
            uv = mapping(tool.get("uv", {}), "tool.uv")
            for spec in strings(uv.get("dev-dependencies", []), "tool.uv.dev-dependencies"):
                parsed = pep508(spec)
                if parsed:
                    emit(*parsed, spec, "tool.uv.dev-dependencies")
            groups = mapping(data.get("dependency-groups", {}), "dependency-groups")
            for group_name, specs in groups.items():
                if not isinstance(specs, list):
                    fail("dependency group must be an array")
                for spec in specs:
                    if isinstance(spec, dict):
                        if set(spec) != {"include-group"} or spec["include-group"] not in groups:
                            fail("unsupported dependency group include")
                        continue
                    parsed = pep508(spec)
                    if parsed:
                        emit(*parsed, spec, f"dependency-groups.{group_name}")
    elif eco == "csproj":
        tree = ET.fromstring(content)
        if tree.tag.split("}")[-1] != "Project":
            fail("NuGet manifest root must be Project")
        for node in tree.iter():
            if node.tag.split("}")[-1] != "PackageReference":
                continue
            name = node.get("Include") or node.get("Update")
            if not name:
                fail("PackageReference requires Include or Update")
            raw = node.get("Version")
            if raw is None:
                versions = [child.text for child in node if child.tag.split("}")[-1] == "Version"]
                raw = versions[0] if versions else None
            if raw is None:
                # Central Package Management remains outside registry checks.
                continue
            selected = version(raw)
            if selected is not None:
                emit(name, selected, xml_dependency_shape(node), "PackageReference")
    else:
        fail(f"unsupported manifest {path}")
    return sorted(set(result))



def dependency_fingerprint(path, content):
    """Keep raw dependency intent, including local sources and version selectors."""
    dependencies(path, content)
    eco = ecosystem(path)
    if eco == "npm":
        data = json.loads(content)
        relevant = {key: data[key] for key in ("dependencies", "devDependencies", "peerDependencies", "optionalDependencies", "overrides") if key in data}
        if "overrides" in data.get("pnpm", {}):
            relevant["pnpm"] = {"overrides": data["pnpm"]["overrides"]}
    elif eco in {"cargo", "pyproject"}:
        data = tomllib.loads(content)
        if eco == "cargo":
            relevant = {}
            def walk(table, prefix):
                for key, value in table.items():
                    if key in {"dependencies", "dev-dependencies", "build-dependencies"}:
                        relevant[".".join(prefix + [key])] = value
                    elif isinstance(value, dict):
                        walk(value, prefix + [key])
            walk(data, [])
        else:
            project = data.get("project", {})
            tool = data.get("tool", {})
            poetry = tool.get("poetry", {})
            relevant = {
                "project": {key: project[key] for key in ("dependencies", "optional-dependencies", "dynamic") if key in project},
                "poetry": {key: poetry[key] for key in ("dependencies", "dev-dependencies", "group") if key in poetry},
                "uv": tool.get("uv", {}),
                "dependency-groups": data.get("dependency-groups", {}),
                "build-system": data.get("build-system", {}).get("requires", []),
            }
    elif eco == "pip":
        relevant = [line.split("#", 1)[0].strip() for line in requirements_lines(content) if line.split("#", 1)[0].strip()]
    else:
        relevant = [xml_dependency_shape(node) for node in ET.fromstring(content).iter() if node.tag.split("}")[-1] == "PackageReference"]
    return json.dumps(relevant, sort_keys=True, separators=(",", ":"))


def state_path(root):
    return root / ".version-sentinel" / "audit.json"


@contextmanager
def state_lock(root, lock_path=None, *, timeout=None):
    """Serialize project transactions; kernel locks release if a process exits."""
    if lock_path is None:
        lock_path = state_path(root).with_suffix(".lock")
    lock_path.parent.mkdir(parents=True, exist_ok=True)
    # Keep this file: unlinking it could let waiters lock different inodes.
    with lock_path.open("a+b") as handle:
        if os.name == "nt":
            import msvcrt
            handle.seek(0)
            flags = msvcrt.LK_LOCK if timeout is None else msvcrt.LK_NBLCK
        else:
            import fcntl
            flags = fcntl.LOCK_EX if timeout is None else fcntl.LOCK_EX | fcntl.LOCK_NB
        deadline = time.monotonic() + timeout if timeout is not None else None
        while True:
            try:
                if os.name == "nt":
                    msvcrt.locking(handle.fileno(), flags, 1)
                else:
                    fcntl.flock(handle.fileno(), flags)
                break
            except OSError:
                if deadline is None or time.monotonic() >= deadline:
                    raise
                time.sleep(0.02)
        try:
            yield
        finally:
            if os.name == "nt":
                handle.seek(0)
                msvcrt.locking(handle.fileno(), msvcrt.LK_UNLCK, 1)
            else:
                fcntl.flock(handle.fileno(), fcntl.LOCK_UN)


def read_json(path, default):
    if not path.exists():
        return default
    data = json.loads(path.read_text())
    if not isinstance(data, dict):
        fail(f"invalid state file {path}")
    return data


def write_json(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    ignore = path.parent / ".gitignore"
    if not ignore.exists():
        ignore.write_text("*\n!.gitignore\n")
    fd, temporary = tempfile.mkstemp(prefix=f".{path.stem}-", dir=path.parent)
    try:
        with os.fdopen(fd, "w") as handle:
            json.dump(data, handle, sort_keys=True)
            handle.write("\n")
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def invalidate_state(root, previous, session=""):
    previous.update(status="pending", root=str(root))
    if session:
        previous["session"] = session
    write_json(state_path(root), previous)


def startup_invalidate(fallback):
    """Resolve startup JSON and revoke target evidence without jq or curl."""
    root = resolve_path(fallback).resolve(strict=True)
    try:
        # Hook JSON is UTF-8 even when native Windows pipes use an ANSI code page.
        if hasattr(sys.stdin, "reconfigure"):
            sys.stdin.reconfigure(encoding="utf-8")
        raw = sys.stdin.read()
        payload = json.loads(raw, object_pairs_hook=unique_object) if raw else {}
        mapping(payload, "startup payload")
        cwd = payload.get("cwd")
        session = payload.get("session_id")
        cwd = "" if cwd is None else cwd
        session = "" if session is None else session
        if not isinstance(cwd, str) or not isinstance(session, str):
            fail("startup cwd and session_id must be strings")
    except (ValueError, TypeError):
        # No valid payload root is available; revoke the fallback evidence.
        with state_lock(root):
            invalidate_state(root, read_json(state_path(root), {}), os.environ.get("VS_SESSION_ID", ""))
        fail("Invalid startup payload; mandatory audit was not completed.")
    if cwd:
        if any(character in cwd for character in "\r\n"):
            fail("Unsupported line break in startup project directory.")
        root = resolve_path(cwd, root).resolve(strict=True)
    if any(character in str(root) for character in "\r\n"):
        fail("Unsupported line break in startup project directory.")
    with state_lock(root):
        invalidate_state(root, read_json(state_path(root), {}), session)
    print(json.dumps({"cwd": root.as_posix(), "session_id": session}))


def usable_path(root, name, *, allow_deep=False):
    path = resolve_path(os.fspath(name), root)
    try:
        relative = path.relative_to(root)
    except ValueError:
        fail(f"manifest is outside project: {path}")
    if any(c in str(relative) for c in "\n\r\t") or (not allow_deep and len(relative.parts) > 4) or any(p in EXCLUDED for p in relative.parts):
        fail(f"manifest is outside supported audit scope: {path}")
    return path, relative_key(path, root)


def in_scope(relative):
    return len(relative.parts) <= 4 and not EXCLUDED.intersection(relative.parts)


def inventory(root, previous, extra_files=()):
    found = set()
    for directory, dirs, files in os.walk(root, followlinks=False):
        relative = Path(directory).relative_to(root)
        dirs[:] = [d for d in dirs if in_scope(relative / d) and len((relative / d).parts) < 4]
        for name in files:
            rel = relative / name
            if in_scope(rel) and (ecosystem(name) or name in LOCKFILES or name in extra_files):
                _, safe = usable_path(root, rel)
                found.add(safe)
    required = {name for name in found if ecosystem(name)}
    for name in previous.get("required", []):
        # Previously audited includes remain required even after deletion.
        _, safe = usable_path(root, name, allow_deep=ecosystem(name) == "pip")
        required.add(safe)
    # Retired deep includes can lie beyond normal discovery. Rediscover them
    # only when present; once found, ordinary required-path tracking resumes.
    for receipt in previous.get("retirements", []):
        name = receipt["file"]
        target, safe = usable_path(root, name, allow_deep=ecosystem(name) == "pip")
        if target.exists():
            required.add(safe)
    tracked = subprocess.run(["git", "-C", str(root), "ls-files", "-z", "--"], capture_output=True) if shutil.which("git") else None
    if tracked is not None and tracked.returncode == 0:
        for name in tracked.stdout.decode().split("\0"):
            rel = Path(name)
            if name and ecosystem(name) and in_scope(rel):
                _, safe = usable_path(root, rel)
                required.add(safe)
    # A lockfile identifies a required source manifest even on first startup.
    for name in found:
        lock = Path(name)
        if lock.name in {"package-lock.json", "npm-shrinkwrap.json", "pnpm-lock.yaml", "yarn.lock", "bun.lock", "bun.lockb"}:
            required.add((lock.parent / "package.json").as_posix())
        elif lock.name in {"poetry.lock", "uv.lock"}:
            required.add((lock.parent / "pyproject.toml").as_posix())
        elif lock.name == "Cargo.lock":
            required.add((lock.parent / "Cargo.toml").as_posix())
    # Include files are dependency manifests too, including nonstandard names.
    todo = list(required)
    while todo:
        name = todo.pop()
        path = root / name
        if not path.is_file() or ecosystem(path) != "pip":
            continue
        for line in requirements_lines(path.read_text()):
            match = re.match(r"\s*(?:-[rc]\s*|--(?:requirement|constraint)(?:\s+|=))([^\s#]+)", line)
            if match:
                # Discovery stays bounded; explicit inputs extend its closure.
                target, safe = usable_path(root, path.parent / match.group(1), allow_deep=True)
                if ecosystem(target) != "pip":
                    fail(f"unsupported requirements include name: {safe}; use requirements*.txt or constraints*.txt")
                if safe not in required:
                    required.add(safe)
                    todo.append(safe)
    files = {}
    for name in sorted(found | required):
        path = root / name
        files[name] = hashlib.sha256(path.read_bytes()).hexdigest() if path.is_file() else None
    return {"root": str(root), "required": sorted(required), "files": files}


def now():
    override = os.environ.get("VS_NOW_OVERRIDE")
    return dt.datetime.strptime(override, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=dt.timezone.utc).timestamp() if override else dt.datetime.now(dt.timezone.utc).timestamp()


def ensure_manifests(root, snapshot):
    if not snapshot["required"]:
        fail("Required dependency manifest is missing. Ask Daniel whether to create/recreate the intended manifest before dependency work; do not guess dependencies. After consent run recover-manifest.sh approve FILE --user-confirmed REASON.")
    for name in snapshot["required"]:
        path = root / name
        if not path.is_file():
            fail(f"Required manifest is missing: {name}. Ask Daniel before recreating it. After consent run recover-manifest.sh approve {name} --user-confirmed REASON.")
        try:
            dependencies(path, path.read_text())
        except (ValueError, ET.ParseError) as error:
            if str(error).startswith("Unsupported dependency-selector"):
                fail(f"Cannot fully audit {name}: {error}. This is a parser limitation; preserve the manifest and add verified parser support before retrying.")
            fail(f"Required manifest is invalid: {name}: {error}. Ask Daniel before repairing/recreating it; use recover-manifest.sh approve FILE --user-confirmed REASON after consent.")


def condition(path):
    if not path.exists():
        return "missing"
    if not path.is_file():
        fail("recovery target must be a file")
    try:
        dependencies(path, path.read_text())
    except (ValueError, ET.ParseError):
        return "invalid:" + hashlib.sha256(path.read_bytes()).hexdigest()
    fail("manifest is valid; recovery cannot authorize replacing it")


def retire_manifest(root, previous, arguments):
    """Remove one stale requirement after user consent and committed deletion proof."""
    if (len(arguments) != 5 or arguments[1] != "--deleted-by"
            or arguments[3] != "--user-confirmed" or not arguments[4].strip()):
        fail("Ask Daniel first; FILE --deleted-by COMMIT --user-confirmed REASON is required")
    name, _, commit, _, reason = arguments
    if not re.fullmatch(r"[0-9a-f]{40}|[0-9a-f]{64}", commit):
        fail("retirement requires the full Git deletion commit ID")
    target, relative = usable_path(root, name, allow_deep=ecosystem(name) == "pip")
    if previous.get("root") != str(root) or relative not in previous.get("required", []):
        fail("retirement requires an existing project-bound required manifest record")
    if not ecosystem(target):
        fail("retirement target is not a supported dependency manifest")
    if os.path.lexists(target):
        fail("retirement target must be absent from the working tree")

    # The audit root may contain several repositories. Find the target's real
    # repository, including when its containing directory was also deleted.
    directory = target.parent
    while not directory.exists() and directory != root:
        directory = directory.parent
    if not shutil.which("git"):
        fail("Git is required to prove a committed manifest deletion")
    # Repository/object overrides must not redirect proof to another checkout.
    environment = {key: value for key, value in os.environ.items() if not key.startswith("GIT_")}

    def git(*args, cwd=directory):
        result = subprocess.run(["git", "--no-replace-objects", "--literal-pathspecs", "-C", str(cwd), *args],
                                capture_output=True, env=environment)
        if result.returncode:
            fail("Git could not prove the requested committed manifest deletion")
        return result.stdout

    repo = Path(os.fsdecode(git("rev-parse", "--show-toplevel")).strip()).resolve(strict=True)
    try:
        git_name = target.relative_to(repo).as_posix()
    except ValueError:
        fail("retirement target is outside its Git repository")
    graft_path = resolve_path(os.fsdecode(git("rev-parse", "--git-path", "info/grafts", cwd=repo)).strip(), repo)
    if graft_path.exists() and graft_path.stat().st_size:
        fail("Git grafts can alter commit ancestry; retirement requires unmodified history")
    head = git("rev-parse", "--verify", "HEAD^{commit}", cwd=repo).decode().strip()
    verified = git("rev-parse", "--verify", commit + "^{commit}", cwd=repo).decode().strip()
    if verified != commit:
        fail("retirement requires an exact commit object")
    git("merge-base", "--is-ancestor", commit, head, cwd=repo)
    parents = git("rev-list", "--parents", "-n", "1", commit, cwd=repo).decode().split()
    if len(parents) != 2:
        fail("retirement requires a deletion commit with exactly one parent")
    parent = parents[1]
    prior = git("ls-tree", "-z", parent, "--", git_name, cwd=repo).split(b"\0")
    if len(prior) != 2 or not prior[0]:
        fail("manifest did not exist in the deletion commit's parent")
    metadata, prior_name = prior[0].split(b"\t", 1)
    mode, kind, blob = metadata.split()
    if mode not in {b"100644", b"100755"} or kind != b"blob" or os.fsdecode(prior_name) != git_name:
        fail("deletion proof must name the exact regular manifest file")
    if (git("ls-tree", "-z", commit, "--", git_name, cwd=repo)
            or git("ls-tree", "-z", head, "--", git_name, cwd=repo)
            or git("ls-files", "-z", "--", git_name, cwd=repo)):
        fail("manifest must be deleted in the supplied commit, HEAD, and index")
    prior_hash = hashlib.sha256(git("cat-file", "blob", blob.decode(), cwd=repo)).hexdigest()
    updated = dict(previous)
    updated["required"] = [entry for entry in previous["required"] if entry != relative]
    # A live include or lockfile still requires its source, even with consent.
    if relative in inventory(root, updated)["required"]:
        fail("manifest remains required by a tracked file, include, or lockfile")
    updated["files"] = dict(previous.get("files", {}))
    updated["files"].pop(relative, None)
    receipt = {"file": relative, "repository": str(repo), "deletionCommit": commit,
               "head": head, "reason": reason, "approvedAt": now(), "previousFileHash": prior_hash}
    updated["retirements"] = [*previous.get("retirements", []), receipt]
    updated.update(status="pending", generation=secrets.token_hex(16))
    updated.pop("checkedAt", None)
    write_json(state_path(root), updated)
    print(f"Retired stale manifest record for {relative}; no dependency checks recorded. Run check-versions.sh for a fresh online audit before dependency work.")


def main():
    command = sys.argv[1]
    if command == "startup-invalidate":
        startup_invalidate(sys.argv[2])
        return
    if command in {"validate", "validate-content", "deps", "deps-content", "deps-intents-content", "dependency-fingerprint-content"}:
        path = resolve_path(sys.argv[2])
        content = sys.stdin.read() if command.endswith("content") else path.read_text()
        parsed = dependencies(path, content, intents=command == "deps-intents-content")
        if command == "deps-intents-content":
            print(json.dumps([{"pkg": pkg, "version": selected, "intent": intent} for pkg, selected, intent in parsed], sort_keys=True))
            return
        if command == "dependency-fingerprint-content":
            print(dependency_fingerprint(path, content))
        if command.startswith("deps"):
            for package, selected in parsed:
                print(f"{package}\t{selected}")
        return
    root = resolve_path(sys.argv[2]).resolve(strict=True)
    with state_lock(root):
        project_command(command, root)


def project_command(command, root):
    # The caller holds the lock from the first read through every state write.
    path = state_path(root)
    previous = read_json(path, {})
    if command == "retire":
        retire_manifest(root, previous, sys.argv[3:])
        return
    if command in {"recovery-allowed", "approve"}:
        target, relative = usable_path(root, sys.argv[3], allow_deep=ecosystem(sys.argv[3]) == "pip")
        if not in_scope(Path(relative)) and relative not in inventory(root, previous)["required"]:
            fail(f"manifest is not a required requirements include: {relative}")
        if not ecosystem(target):
            fail("recovery target is not a supported dependency manifest")
        current = condition(target)
        approval_path = path.parent / "recovery.json"
        approvals = read_json(approval_path, {"root": str(root), "approvals": {}})
        if approvals.get("root") != str(root):
            fail("recovery approval belongs to a different project")
        if command == "approve":
            if len(sys.argv) != 6 or sys.argv[4] != "--user-confirmed" or not sys.argv[5].strip():
                fail("Ask Daniel first; explicit --user-confirmed REASON is required")
            approvals.setdefault("approvals", {})[relative] = {"condition": current, "reason": sys.argv[5], "approvedAt": now()}
            write_json(approval_path, approvals)
            print(f"Recovery consent recorded for {relative}; no file created. Verify dependencies online, recover only the approved file, then rerun check-versions.sh.")
        else:
            approval = approvals.get("approvals", {}).get(relative, {})
            age = now() - approval.get("approvedAt", 0)
            if approval.get("condition") != current or not 0 <= age <= 86400:
                fail(f"Ask Daniel before recreating/repairing {relative}; no current user-confirmed recovery approval")
        return
    if command == "invalidate":
        invalidate_state(root, previous, os.environ.get("VS_SESSION_ID", ""))
        return
    if command in {"begin", "begin-if-present"}:
        # Revoke old successful evidence before file validation or network access.
        pending = dict(previous)
        pending.update(status="pending", generation=secrets.token_hex(16), root=str(root))
        write_json(path, pending)
        snapshot = inventory(root, previous)
        pending.update(snapshot)
        write_json(path, pending)
        if command == "begin" or snapshot["required"] or snapshot["files"]:
            ensure_manifests(root, snapshot)
        snapshot["generation"] = pending["generation"]
        print(json.dumps(snapshot, sort_keys=True))
        return
    snapshot = inventory(root, previous)
    ensure_manifests(root, snapshot)
    if command == "manifests":
        for name in snapshot["required"]:
            print(root / name)
    elif command == "complete":
        started = json.loads(sys.argv[3])
        if previous.get("status") != "pending" or previous.get("generation") != started.get("generation") or any(started.get(key) != snapshot[key] for key in snapshot):
            fail("project manifests changed while the audit ran; rerun check-versions.sh")
        snapshot.update(status="complete", generation=started["generation"], checkedAt=now(), session=os.environ.get("VS_SESSION_ID") or previous.get("session", ""))
        if "retirements" in previous:
            snapshot["retirements"] = previous["retirements"]
        write_json(path, snapshot)
    elif command in {"gate", "covers"}:
        age = now() - previous.get("checkedAt", 0)
        window = float(os.environ.get("VS_WINDOW_HOURS", "24")) * 3600
        session = os.environ.get("VS_SESSION_ID", "")
        if previous.get("status") != "complete" or not 0 <= age <= window or any(previous.get(key) != snapshot[key] for key in snapshot) or (session and previous.get("session") != session):
            fail("Startup dependency audit is missing, failed, expired, or project files changed. Run bash scripts/check-versions.sh in this project before dependency work. Reading files and requesting recovery consent remain allowed.")
        if command == "covers":
            _, relative = usable_path(root, sys.argv[3], allow_deep=ecosystem(sys.argv[3]) == "pip")
            if relative not in snapshot["files"] or snapshot["files"][relative] is None:
                fail(f"Manifest {relative} was not included in the successful audit; use a supported manifest inside this project and rerun check-versions.sh")
    else:
        fail("unsupported audit-state command")


if __name__ == "__main__":
    try:
        sys.stdout.reconfigure(newline="\n")
        main()
    except (ValueError, OSError, ET.ParseError, KeyError, TypeError, IndexError) as error:
        print(f"BLOCKED: version-sentinel. {error}", file=sys.stderr)
        sys.exit(2)
