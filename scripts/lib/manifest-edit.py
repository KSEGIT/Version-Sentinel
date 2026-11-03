#!/usr/bin/env python3
"""Inspect proposed edits without writing files or executing patch text.

Patch matching is deliberately exact. Unsupported/fuzzy patches must be retried
with full file content; a guessed post-image cannot authorize dependency work.
"""
import fnmatch
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys

SCRIPTS = Path(__file__).resolve().parent.parent
UNPINNED = "__version_sentinel_unpinned__"


class Blocked(Exception):
    pass


def ecosystem(path):
    name = Path(path).name
    if name == "package.json":
        return "npm"
    if any(fnmatch.fnmatch(name, pat) for pat in ("requirements*.txt", "constraints*.txt")):
        return "pip"
    if name == "pyproject.toml":
        return "pyproject"
    if name == "Cargo.toml":
        return "cargo"
    if any(name.endswith(ext) for ext in (".csproj", ".fsproj", ".vbproj")):
        return "csproj"
    return None


def text(value, label):
    if not isinstance(value, str):
        raise Blocked(f"Unsupported {label}; expected text. Retry with full file content.")
    return value


def relevant(root, name):
    # Write/Edit can follow a symlink whose basename hides the manifest.
    return ecosystem(name) or ecosystem((root / Path(name)).resolve())


def run(args, root, content=None):
    return subprocess.run(args, cwd=root, input=content, capture_output=True,
                          text=True, timeout=30, check=False)


def state(action, root, *args, content=None):
    return run(["bash", str(SCRIPTS / "audit-state.sh"), action, *map(str, args)], root, content)


def target(root, name):
    path = Path(text(name, "file path"))
    path = (root / path).resolve()
    if not path.is_relative_to(root):
        raise Blocked(f"Manifest path is outside audited project {root}: {path}")
    return path


def read(path):
    if not path.exists():
        return None
    if not path.is_file():
        raise Blocked(f"Manifest is not a regular file: {path}")
    return path.read_text(encoding="utf-8")


def replace(content, edit):
    if content is None:
        raise Blocked("Edit targets a missing file. Ask Daniel before recreating the manifest.")
    old = text(edit.get("old_string"), "old_string")
    new = text(edit.get("new_string"), "new_string")
    all_matches = edit.get("replace_all", False)
    if not isinstance(all_matches, bool) or not old:
        raise Blocked("Unsupported or empty replacement; retry with full file content.")
    count = content.count(old)
    if count == 0 or (count > 1 and not all_matches):
        raise Blocked("Replacement does not identify one exact manifest post-image.")
    return content.replace(old, new) if all_matches else content.replace(old, new, 1)


def patch_update(content, lines):
    if content is None:
        raise Blocked("Patch targets a missing manifest. Ask Daniel before recreating it.")
    current = content.splitlines()
    cursor = 0
    i = 0
    while i < len(lines):
        if not lines[i].startswith("@@"):
            raise Blocked("Unsupported manifest patch hunk; retry with full content.")
        i += 1
        before, after = [], []
        eof = False
        while i < len(lines) and not lines[i].startswith("@@"):
            line = lines[i]
            i += 1
            if line == "*** End of File":
                eof = True
                continue
            if not line or line[0] not in " +-":
                raise Blocked("Malformed manifest patch line; retry with full content.")
            if line[0] in " -":
                before.append(line[1:])
            if line[0] in " +":
                after.append(line[1:])
        if not before:
            raise Blocked("Manifest patch insertion needs exact context or full content.")
        matches = [n for n in range(cursor, len(current) - len(before) + 1)
                   if current[n:n + len(before)] == before
                   and (not eof or n + len(before) == len(current))]
        if len(matches) != 1:
            raise Blocked("Manifest patch context is missing or ambiguous; retry with full content.")
        start = matches[0]
        current[start:start + len(before)] = after
        cursor = start + len(after)
    return "\n".join(current) + ("\n" if content.endswith("\n") else "")


def patch_operations(root, patch):
    lines = text(patch, "patch body").splitlines()
    if not lines or lines[0] != "*** Begin Patch" or lines[-1] != "*** End Patch":
        raise Blocked("Malformed apply_patch payload; retry with a complete patch.")
    operations = []
    seen = set()
    i = 1
    while i < len(lines) - 1:
        header = re.fullmatch(r"\*\*\* (Add|Update|Delete) File: (.+)", lines[i])
        if not header:
            raise Blocked("Unsupported apply_patch section; retry with full file content.")
        action, name = header.groups()
        name = name.strip()
        i += 1
        body = []
        while i < len(lines) - 1 and not re.match(r"\*\*\* (?:Add|Update|Delete) File:", lines[i]):
            body.append(lines[i])
            i += 1
        move = body[0][len("*** Move to: "):].strip() if body and body[0].startswith("*** Move to: ") else None
        if not relevant(root, name) and not (move and relevant(root, move)):
            continue
        path = target(root, name)
        if path in seen:
            raise Blocked("Repeated manifest patch target; combine edits into one section.")
        seen.add(path)
        if action == "Delete" or move:
            raise Blocked(f"Deleting or moving a required manifest is blocked: {path}. "
                          "Ask Daniel before changing the manifest inventory; restore/recreate only with consent.")
        before = read(path)
        if action == "Add":
            if before is not None:
                raise Blocked(f"Add File would overwrite existing manifest: {path}")
            if any(not line.startswith("+") for line in body):
                raise Blocked("Malformed Add File manifest patch.")
            after = "\n".join(line[1:] for line in body) + "\n"
        else:
            after = patch_update(before, body)
        operations.append((path, before, after))
    return operations


def operations(root, tool, data):
    if tool == "apply_patch":
        if isinstance(data, str):
            return patch_operations(root, data)
        if not isinstance(data, dict):
            raise Blocked("Malformed apply_patch tool_input.")
        patch = data.get("patch", data.get("input", data.get("command")))
        if patch is not None:
            return patch_operations(root, patch)
        tool = "Write"
    if not isinstance(data, dict):
        raise Blocked("Malformed edit tool_input.")
    if "file_path" in data and "path" in data and data["file_path"] != data["path"]:
        raise Blocked("Conflicting file_path/path fields; retry with one exact file path.")
    if "files" in data:
        if "file_path" in data or "path" in data:
            raise Blocked("Mixed single-file/multi-file payload; retry with unambiguous file entries.")
        if not isinstance(data["files"], list) or not data["files"]:
            raise Blocked("Unsupported multi-file edit payload.")
        result = []
        for entry in data["files"]:
            result.extend(operations(root, tool, entry))
        return result
    name = data.get("file_path", data.get("path"))
    if name is None:
        raise Blocked("Unsupported edit payload: missing file path. Retry each file with full content.")
    if not relevant(root, text(name, "file path")):
        return []
    path = target(root, name)
    before = read(path)
    if tool in ("Write", "write_file", "createFile", "save_file"):
        after = text(data.get("content", data.get("new_content")), "manifest content")
    elif tool.lower() == "multiedit":
        edits = data.get("edits")
        if not isinstance(edits, list) or not edits:
            raise Blocked("Unsupported MultiEdit payload.")
        after = before
        for edit in edits:
            if not isinstance(edit, dict):
                raise Blocked("Malformed MultiEdit entry.")
            after = replace(after, edit)
    elif tool in ("Edit", "replace", "editFiles", "edit_file"):
        after = replace(before, data)
    else:
        raise Blocked(f"Unsupported manifest edit tool: {tool}")
    return [(path, before, after)]


def dependency_intents(root, path, content):
    result = state("deps-intents-content", root, path, content=content)
    if result.returncode:
        raise Blocked(f"Could not parse dependencies in {path}; {result.stderr.strip()}")
    entries = json.loads(result.stdout)
    if not isinstance(entries, list):
        raise Blocked(f"Unsupported dependency result for {path}")
    intents = set()
    for entry in entries:
        if (not isinstance(entry, dict) or
                not all(isinstance(entry.get(key), str) for key in ("pkg", "version", "intent"))):
            raise Blocked(f"Unsupported dependency intent for {path}")
        intents.add((entry["pkg"], entry["version"], entry["intent"]))
    return intents


def fingerprint(root, path, content):
    result = state("dependency-fingerprint-content", root, path, content=content)
    if result.returncode:
        raise Blocked(f"Cannot distinguish dependency changes in {path}: {result.stderr.strip()}")
    return result.stdout


def inspect(root, proposed):
    errors = []
    checked_audit = None
    for path, before, after in proposed:
        valid_before = before is not None and state("validate-content", root, path, content=before).returncode == 0
        recovery = False
        if not valid_before:
            recovery = state("recovery-allowed", root, root, path).returncode == 0
            if not recovery:
                errors.append(f"Missing or invalid required manifest: {path}. Ask Daniel before recreating it. "
                              "After explicit consent, run recover-manifest.sh approve FILE --user-confirmed REASON.")
        validation = state("validate-content", root, path, content=after)
        if validation.returncode:
            errors.append(f"Invalid proposed manifest {path}: {validation.stderr.strip()}")
            continue
        pre_intents = dependency_intents(root, path, before) if valid_before else set()
        post_intents = dependency_intents(root, path, after)
        same_dependency_fields = (valid_before and
                                  fingerprint(root, path, before) == fingerprint(root, path, after))
        if pre_intents == post_intents and same_dependency_fields:
            continue
        if not recovery:
            if checked_audit is None:
                checked_audit = state("gate", root, root)
            if checked_audit.returncode:
                errors.append(checked_audit.stderr.strip() or "Complete the mandatory online audit before dependency work.")
            elif valid_before:
                covered = state("covers", root, root, path)
                if covered.returncode:
                    errors.append(covered.stderr.strip() or f"Manifest was not audited: {path}")
        # Keep each raw declaration's intent, so a selector-only edit still
        # needs verification when its parsed intended version is unchanged.
        changed = {(pkg, version) for pkg, version, _ in post_intents - pre_intents}
        for pkg, version in sorted(changed):
            eco = ecosystem(path)
            if version == UNPINNED:
                errors.append(f"Package: {pkg} ({eco}). No explicit registry version was provided. "
                              "Record an exact online-verified version and retry.")
                continue
            record = run(["bash", str(SCRIPTS / "check-sidecar.sh"), eco, pkg, version], root)
            if record.returncode:
                errors.append(record.stderr.strip() or f"No online verification for {pkg}@{version}.")
    if errors:
        raise Blocked("\n---\n".join(dict.fromkeys(errors)))


def main():
    payload = json.load(sys.stdin)
    if not isinstance(payload, dict):
        raise Blocked("Hook payload must be a JSON object.")
    tool = text(payload.get("tool_name"), "tool_name")
    if tool in ("Bash", "exec_command", "runTerminalCommand", "run_shell_command", "terminal",
                "Read", "read_file", "Glob", "Grep"):
        return
    session = payload.get("session_id")
    if session is not None:
        session = text(session, "session_id")
        if session:
            os.environ["VS_SESSION_ID"] = session
    root = Path(text(payload.get("cwd", os.getcwd()), "project cwd")).resolve()
    proposed = operations(root, tool, payload.get("tool_input"))
    if not proposed:
        return
    if not shutil.which("jq"):
        raise Blocked("jq is required to inspect registry dependencies.")
    inspect(root, proposed)


if __name__ == "__main__":
    try:
        main()
    except (Blocked, OSError, ValueError, TypeError, subprocess.SubprocessError) as error:
        print(f"BLOCKED: version-sentinel. {error}", file=sys.stderr)
        sys.exit(2)
