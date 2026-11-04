#!/usr/bin/env python3
"""Find literal project contexts for dependency operations; never execute shell input.

This is a conservative command recognizer, not a shell interpreter. Dynamic
directories and shell constructs around a dependency command require separate,
literal tool calls. Arbitrary programs that write manifests remain out of scope.
"""
import json
import re
from pathlib import Path
import shlex
import sys

from path_helpers import resolve_path


OPERATIONS = {
    "npm": {"add", "install", "i", "ci", "update", "up", "run", "test", "rebuild", "exec"},
    "pnpm": {"add", "install", "i", "update", "up", "run", "test", "build", "exec"},
    "yarn": {"add", "install", "up", "upgrade", "run", "test", "build", "exec"},
    "bun": {"add", "install", "i", "update", "run", "test", "build"},
    "pip": {"install", "download"},
    "pip3": {"install", "download"},
    "poetry": {"add", "install", "sync", "update", "lock", "build", "run"},
    "uv": {"add", "sync", "update", "lock", "build", "run", "pip"},
    "cargo": {"add", "install", "update", "fetch", "build", "check", "test", "run"},
    "dotnet": {"add", "restore", "build", "test", "run", "publish", "package"},
}
for _manager in OPERATIONS:
    OPERATIONS[_manager].update({"init", "new"})
DIR_FLAGS = {"--prefix", "--cwd", "--dir", "--directory", "--project", "-C"}
FILE_FLAGS = {"--manifest-path", "--project-file", "--requirement", "--constraint", "-r", "-c"}
SEPARATORS = {"&&", "||", ";", "|", "&", "\n"}


def literal_path(base, raw):
    if not raw or any(c in raw for c in "$`*?{}\n") or raw.startswith("~"):
        raise ValueError("dynamic dependency directory/file; use a literal path in a separate tool call")
    return resolve_path(raw, base)


def remove_redirections(command):
    """Remove literal redirections while keeping fd/word source adjacency.

    Quotes and escaped characters are retained for shlex. Unsupported shell
    redirection forms remain intact and are rejected for dependency commands.
    """
    output = ""
    i, quote = 0, ""
    while i < len(command):
        char = command[i]
        if char == "\\" and quote != "'" and i + 1 < len(command):
            if command[i + 1] != "\n":
                output += command[i:i + 2]
            i += 2
            continue
        if quote:
            output += char
            if char == quote:
                quote = ""
            i += 1
            continue
        if char in "\"'":
            quote = char
            output += char
            i += 1
            continue
        if command.startswith("<<", i):
            # Heredoc bodies are not ordinary shell words.
            return output + command[i:], True
        operator = re.match(r"&>>|&>|>>|>\||>&|<>|<&|>|<", command[i:])
        if not operator:
            output += char
            i += 1
            continue
        op = operator.group()
        target_start = i + len(op)
        while target_start < len(command) and command[target_start] in " \t":
            target_start += 1
        end, target_quote = target_start, ""
        while end < len(command):
            current = command[end]
            if current == "\\" and target_quote != "'" and end + 1 < len(command):
                end += 2
                continue
            if target_quote:
                if current == target_quote:
                    target_quote = ""
            elif current in "\"'":
                target_quote = current
            elif current in " \t\r\n;&|()<>":
                break
            end += 1
        raw_target = command[target_start:end]
        if not raw_target or target_quote or "$(" in raw_target or "`" in raw_target:
            return output + command[i:], True
        if not op.startswith("&"):
            # Only an adjacent all-digit word is a descriptor. `2 >log`
            # keeps the package `2`; `2>log` is purely a redirect.
            descriptor = re.search(r"(?:^|[\s;&|()])([0-9]+)$", output)
            if descriptor:
                output = output[:descriptor.start(1)]
        output += " "
        i = end
    return output, False


def contexts(base, command):
    command, unsupported_redirection = remove_redirections(command)
    lexer = shlex.shlex(command, posix=True, punctuation_chars=";&|()<>\n")
    lexer.whitespace = " \t\r"
    lexer.whitespace_split = True
    lexer.commenters = "#"
    tokens = list(lexer)
    has_operation = any(Path(w).name in OPERATIONS and (
        any(t in OPERATIONS[Path(w).name] or "$" in t or "`" in t for t in tokens[i + 1:])
        or Path(w).name == "yarn") for i, w in enumerate(tokens))
    if not has_operation:
        return []
    if unsupported_redirection:
        raise ValueError("unsupported shell redirection around dependency operation; use separate literal tool calls")
    if "cd" in tokens and any(t in {"||", ";", "|", "&"} for t in tokens):
        raise ValueError("directory changes with shell fallback need separate literal tool calls")
    segments, segment = [], []
    for tok in tokens:
        if tok in SEPARATORS:
            if segment:
                segments.append(segment)
            segment = []
        else:
            segment.append(tok)
    if segment:
        segments.append(segment)
    cwd = resolve_path(base)
    result = []
    for words in segments:
        if words[0] in {"echo", "printf", "cat", "rg", "grep"}:
            continue
        if words[0] == "cd":
            if len(words) != 2:
                raise ValueError("cannot determine dependency command directory; use separate tool calls")
            cwd = literal_path(cwd, words[1])
            continue
        manager_index = next((i for i, w in enumerate(words) if Path(w).name in OPERATIONS), None)
        if manager_index is None:
            continue
        if "env" in words[:manager_index] and any(w.startswith(("-S", "--split-string")) for w in words[:manager_index]):
            raise ValueError("env -S command strings cannot be inspected safely")
        prefix = words[:manager_index]
        if any(w in {"-C", "-D", "--chdir"} or w.startswith(("--chdir=", "-C", "-D")) for w in prefix):
            raise ValueError("directory-changing wrapper needs an explicit literal cd tool call")
        manager = Path(words[manager_index]).name
        rest = words[manager_index + 1:]
        # Yarn installs by default, including when only install flags/cwd
        # are supplied. Version/help flags remain inspection operations.
        yarn_default = manager == "yarn" and (not rest or rest[0].startswith("-"))
        # Read-only manager calls remain available without an audit.
        if not any(w in OPERATIONS[manager] for w in rest) and not yarn_default:
            if any("$" in w or "`" in w for w in rest):
                raise ValueError("dynamic package-manager command; use literal arguments")
            continue
        if any(w in {"(", ")", "<<", "<<-", "<<<"} for w in words):
            raise ValueError("unsupported shell construct around dependency operation; use separate tool calls")
        if any(re.match(r"^[0-9]*[<>]", word) for word in rest):
            # These survived quote-aware redirect removal, so they are
            # literal package words. The legacy parser cannot preserve that
            # distinction; fail closed instead of dropping an argument.
            raise ValueError("literal redirection-like package arguments cannot be inspected safely")
        root, required, normalized = cwd, [], []
        i = 0
        while i < len(rest):
            word = rest[i]
            flag, equal, attached = word.partition("=")
            # -rfile and -Cdir are supported by their respective managers.
            if not equal and len(word) > 2 and word[:2] in {"-C", "-r", "-c"}:
                flag, attached, equal = word[:2], word[2:], "="
            file_flags = FILE_FLAGS if manager in {"pip", "pip3", "uv"} else {"--manifest-path", "--project-file"}
            if flag in DIR_FLAGS or flag in file_flags:
                if not equal:
                    i += 1
                    if i >= len(rest):
                        raise ValueError("missing dependency directory/file option value")
                    attached = rest[i]
                target = literal_path(cwd, attached)
                if flag in DIR_FLAGS:
                    root = target.parent if target.suffix in {".toml", ".csproj", ".fsproj", ".vbproj"} else target
                else:
                    required.append(str(target))
                    if flag in {"--manifest-path", "--project-file"}:
                        root = target.parent
                i += 1
                continue
            normalized.append(word)
            i += 1
        if manager == "yarn" and normalized and all(w in {"-v", "--version", "-h", "--help"} for w in normalized):
            continue
        if yarn_default and (not normalized or normalized[0].startswith("-")):
            if any(w in OPERATIONS[manager] for w in normalized):
                raise ValueError("unsupported Yarn option ordering; put the explicit operation before its options")
            normalized.insert(0, "install")
        if normalized and normalized[0] not in OPERATIONS[manager]:
            raise ValueError("unsupported package-manager option ordering; put the operation before its options")
        if ((manager == "cargo" and normalized and normalized[0] == "install")
                or (manager in {"npm", "pnpm", "yarn"} and normalized and normalized[0] == "exec")
                or any(w == "--with" or w.startswith(("--with=", "--with-requirements", "--with-editable")) for w in normalized)):
            raise ValueError("direct dependency resolution is not safely inspectable; add exact online-verified dependencies to a reviewed manifest and rerun the audit first")
        if normalized and normalized[0] in {"init", "new"}:
            raise ValueError("manifest creation requires user-confirmed recovery; ask Daniel, write reviewed contents with verified dependencies, and rerun the audit")
        if normalized and normalized[0] in {"update", "up", "upgrade"}:
            raise ValueError("floating dependency updates need explicit package versions; verify and record each intended version, then edit the manifest")
        # dotnet accepts project paths as positional arguments.
        if manager == "dotnet":
            for word in normalized:
                if word.endswith((".csproj", ".fsproj", ".vbproj")):
                    target = literal_path(cwd, word)
                    root = target.parent
                    required.append(str(target))
            normalized = [w for w in normalized if not w.endswith((".csproj", ".fsproj", ".vbproj"))]
        if any("$" in w or "`" in w for w in normalized):
            raise ValueError("dynamic dependency operation; use literal package and version arguments")
        # A successful audit of a different ecosystem must never authorize
        # package-manager creation of its missing source manifest.
        if manager in {"npm", "pnpm", "yarn", "bun"}:
            required.append(str(root / "package.json"))
        elif manager == "cargo":
            required.append(str(root / "Cargo.toml"))
        elif manager == "dotnet":
            projects = sorted(p for p in root.glob("*.*proj") if p.suffix in {".csproj", ".fsproj", ".vbproj"})
            if not required:
                required.extend(map(str, projects or [root / "Project.csproj"]))
        elif manager == "poetry" or (manager == "uv" and (not normalized or normalized[0] != "pip")):
            required.append(str(root / "pyproject.toml"))
        elif not required:
            manifests = sorted(root.glob("requirements*.txt"))
            if not manifests and (root / "pyproject.toml").is_file():
                manifests = [root / "pyproject.toml"]
            required.extend(map(str, manifests or [root / "requirements.txt"]))
        result.append({"root": str(root), "required": sorted(set(required)),
                       "command": shlex.join([manager, *normalized])})
    return result


if __name__ == "__main__":
    try:
        if sys.argv[1] == "--payload-root":
            payload = json.load(sys.stdin)
            base = payload.get("cwd", str(Path.cwd()))
            data = payload.get("tool_input", {})
            if not isinstance(base, str) or not isinstance(data, dict):
                raise ValueError("malformed command project context")
            overrides = [data[k] for k in ("workdir", "dir_path", "cwd") if k in data and data[k] is not None]
            if any(not isinstance(v, str) for v in overrides) or len(set(overrides)) > 1:
                raise ValueError("malformed or conflicting command directory overrides")
            print(literal_path(resolve_path(base), overrides[0]) if overrides else resolve_path(base))
        else:
            print(json.dumps(contexts(sys.argv[1], sys.argv[2])))
    except (ValueError, OSError, IndexError) as exc:
        print(f"BLOCKED: version-sentinel. Cannot safely inspect command: {exc}", file=sys.stderr)
        sys.exit(2)
