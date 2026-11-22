#!/usr/bin/env python3
"""Remember local advisory diagnostics. A failure leaves the warning visible."""
import hashlib
import json
import os
from pathlib import Path
import re
import runpy
import shlex
import sys

from path_helpers import resolve_path

LIB = Path(__file__).resolve().parent
CACHE = "warning-history.json"
MAX_SCOPES = 64
MAX_DIAGNOSTICS = 16
MAX_CACHE_BYTES = 96 * 1024
EVIDENCE = ("audit.json", "checks.json", "security.json")
SETTINGS = ("WINDOW_HOURS", "SECURITY_NPM_AUDIT", "SECURITY_OSV")
# Build/test/run commands can use dependencies without proposing new versions.
NO_PROPOSAL = {"run", "test", "build", "check", "publish"}
HEX_DIGEST = re.compile(r"[a-f0-9]{64}")


def digest(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True).encode()).hexdigest()


def file_digest(path):
    if not path.exists():
        return None
    if not path.is_file():
        raise ValueError("warning state requires regular files")
    with path.open("rb") as handle:
        return hashlib.file_digest(handle, "sha256").hexdigest()


def hook_scope(validator, payload):
    tool = payload["tool_name"]
    data = payload["tool_input"]
    post = runpy.run_path(str(LIB / "security-post.py"))
    base = resolve_path(payload.get("cwd", str(Path.cwd())))
    if tool in post["SHELL_TOOLS"] and validator != "validate-detect-manifest-edit.sh":
        parser = runpy.run_path(str(LIB / "install-context.py"))
        base = parser["payload_root"](payload)
        command = data.get("command", data.get("cmd"))
        contexts = parser["contexts"](str(base), command)
        if validator == "validate-auto-record.sh":
            roots = post["shell_roots"](base, command, contexts, parser["leading_directory"])
        else:
            # Unrecognized syntax and install hooks that did no work cannot
            # identify which earlier diagnostic a success should clear.
            roots = {resolve_path(context["root"]) for context in contexts}
        proposals = [context for context in contexts
                     if shlex.split(context["command"])[1] not in NO_PROPOSAL]
        required = {resolve_path(path) for context in contexts for path in context["required"]}
        return roots, proposals, required
    if validator == "validate-detect-manifest-edit.sh":
        edit = runpy.run_path(str(LIB / "manifest-edit.py"))
        try:
            operations = edit["operations"](base, tool, data)
        except edit["Blocked"] as error:
            raise ValueError("cannot identify manifest proposal") from error
        proposals = [(path.as_posix(), after) for path, _, after in operations]
        return {base} if operations else set(), proposals, set()
    if validator == "validate-auto-record.sh" and tool in post["EDIT_TOOLS"] and post["npm_paths"](data, base):
        return {base}, [], set()
    return set(), [], set()


def dependency_state(roots, required, project):
    inputs = []
    discovered = set()
    checks_root = os.environ.get("VS_PROJECT_ROOT")
    for root in sorted(roots):
        directory = root / ".version-sentinel"
        try:
            previous = project["read_json"](directory / "audit.json", {})
        except ValueError:
            # Invalid audit bytes still distinguish the observed evidence.
            previous = {}
        inventory = project["inventory"](root, previous, extra_files={".npmrc"})
        discovered.update(root / name for name in inventory["files"])
        inputs.append((inventory, [file_digest(directory / name) for name in EVIDENCE]))
        if checks_root:
            override = resolve_path(checks_root, root) / ".version-sentinel"
            inputs.append([file_digest(override / name) for name in EVIDENCE])
    settings = [os.environ.get("VS_" + key, os.environ.get("CLAUDE_PLUGIN_OPTION_" + key))
                for key in SETTINGS]
    explicit_files = []
    for path in sorted(required - discovered):
        if not any(path.is_relative_to(root) for root in roots):
            raise ValueError("explicit dependency file outside inspected roots")
        explicit_files.append((str(path), file_digest(path)))
    return digest((inputs, settings, checks_root, explicit_files))


def read_history(path, unique_object):
    if path.is_symlink():
        raise ValueError("warning history cannot be a symlink")
    if not path.exists():
        return {}
    if not path.is_file() or not os.access(path, os.W_OK):
        raise ValueError("warning history is not writable")
    with path.open("rb") as handle:
        raw = handle.read(MAX_CACHE_BYTES + 1)
    if len(raw) > MAX_CACHE_BYTES:
        raise ValueError("warning history is too large")
    history = json.loads(raw, object_pairs_hook=unique_object)
    if not isinstance(history, dict) or len(history) > MAX_SCOPES:
        raise ValueError("invalid warning history")
    for scope, entry in history.items():
        if (not HEX_DIGEST.fullmatch(scope) or not isinstance(entry, list) or len(entry) != 2
                or not isinstance(entry[0], str) or not HEX_DIGEST.fullmatch(entry[0])
                or not isinstance(entry[1], list) or not 0 < len(entry[1]) <= MAX_DIAGNOSTICS
                or any(not isinstance(value, str) or not HEX_DIGEST.fullmatch(value) for value in entry[1])):
            raise ValueError("invalid warning history entry")
    return history


def warning_seen(validator, payload, diagnostic):
    _, _, warning, _ = diagnostic.split(b"\0")
    roots, proposals, required = hook_scope(validator, payload)
    if not roots or not all(root.is_dir() for root in roots):
        return False
    # Choose one stable owner even when a tool call checked multiple roots.
    path = min(roots) / ".version-sentinel" / CACHE
    if not warning and not path.exists():
        return False
    if (path.parent.is_symlink() or (path.parent / ".gitignore").is_symlink()
            or (path.parent.exists() and not os.access(path.parent, os.W_OK))):
        return False
    scope = digest((validator, sorted(map(str, roots)), proposals))
    project = runpy.run_path(str(LIB / "project-state.py"))
    current = dependency_state(roots, required, project) if warning else None
    lock = path.with_suffix(".lock")
    if lock.is_symlink() or (lock.exists() and not lock.is_file()):
        return False
    # A stalled cache writer must not delay tool use.
    with project["state_lock"](min(roots), lock, timeout=0.5):
        history = read_history(path, project["unique_object"])
        if not warning:
            if scope in history:
                del history[scope]
                project["write_json"](path, history)
            return False
        previous, diagnostics = history.get(scope, (None, []))
        # Full diagnostics can differ even when the compact warning does not.
        # Compare the latest warning so a returning diagnostic is shown again.
        diagnostic = hashlib.sha256(diagnostic).hexdigest()
        if previous == current and diagnostics and diagnostics[-1] == diagnostic:
            return True
        history[scope] = (current, [diagnostic])
        if len(history) > MAX_SCOPES:
            del history[next(iter(history))]
        project["write_json"](path, history)
    return False


if __name__ == "__main__":
    try:
        payload = json.loads(resolve_path(sys.argv[2]).read_bytes())
        sys.exit(0 if warning_seen(sys.argv[1], payload, sys.stdin.buffer.read()) else 1)
    except (OSError, ValueError, TypeError, AttributeError, RuntimeError, KeyError, IndexError):
        sys.exit(1)
