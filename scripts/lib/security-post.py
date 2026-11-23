#!/usr/bin/env python3
"""Rescan changed npm state after supported mutation tools; never record checks."""
import json
import os
from pathlib import Path
import re
import runpy
import shutil
import subprocess
import sys

from path_helpers import bash_script_path, resolve_path

SCRIPTS = Path(__file__).resolve().parent.parent
NPM_FILES = {"package.json", "package-lock.json", "npm-shrinkwrap.json", "pnpm-lock.yaml", "yarn.lock", "bun.lock", "bun.lockb"}
SHELL_TOOLS = {"Bash", "exec_command", "runTerminalCommand", "run_shell_command", "terminal"}
EDIT_TOOLS = {"Edit", "Write", "MultiEdit", "apply_patch", "editFiles", "createFile", "write_file", "replace"}


def npm_paths(value, root):
    if isinstance(value, dict):
        return any(npm_paths(v, root) for k, v in value.items()
                   if k in {"file_path", "path", "target_file", "filePath", "patch", "input", "command", "edits", "files", "changes"})
    if isinstance(value, list):
        return any(npm_paths(v, root) for v in value)
    if isinstance(value, str):
        return ("\n" not in value and resolve_path(value, root).name in NPM_FILES) or bool(re.search(
            r"^\*\*\* (?:Add|Update|Delete) File: .*?(?:package(?:-lock)?\.json|npm-shrinkwrap\.json|pnpm-lock\.yaml|yarn\.lock|bun\.lockb?)$", value, re.M))
    return False


def shell_roots(base, command, contexts, leading_directory):
    # A literal cd can select a separate project, even from its source folder.
    # Inside the base, stop at the base if no closer boundary owns the snapshot.
    effective = leading_directory(base, command)
    if effective != base:
        boundaries = NPM_FILES | {".git", ".version-sentinel/security.json"}
        for directory in (effective, *effective.parents):
            if directory == base or any((directory / name).exists() for name in boundaries):
                effective = directory
                break
    roots = {effective}
    roots.update(resolve_path(context["root"]) for context in contexts
                 if any(Path(p).name == "package.json" for p in context["required"]))
    return roots


def main():
    raw = sys.stdin.read()
    if not raw.strip():
        return
    payload = json.loads(raw)
    if not isinstance(payload, dict):
        raise ValueError("PostToolUse payload must be an object")
    tool = payload.get("tool_name", "")
    if tool not in SHELL_TOOLS | EDIT_TOOLS:
        return
    data = payload.get("tool_input", {})
    if not isinstance(data, (dict, str)):
        raise ValueError("PostToolUse input cannot be inspected")
    root = resolve_path(payload.get("cwd", os.getcwd()))
    roots = set()
    if tool in SHELL_TOOLS:
        parser = runpy.run_path(str(SCRIPTS / "lib/install-context.py"))
        root = parser["payload_root"](payload)
        command = data.get("command", data.get("cmd", ""))
        if not isinstance(command, str):
            raise ValueError("PostToolUse command must be text")
        try:
            contexts = parser["contexts"](str(root), command)
            roots = shell_roots(root, command, contexts, parser["leading_directory"])
        except ValueError:
            # Dependency syntax can fail even when a literal cd is resolvable.
            try:
                roots = shell_roots(root, command, [], parser["leading_directory"])
            except ValueError:
                # Keep the known workdir when directory inference also fails.
                roots = {root}
    elif npm_paths(data, root):
        roots.add(root)
    bash = shutil.which("bash")
    if roots and not bash:
        raise ValueError("bash is required for PostToolUse security checks")
    for target in sorted(roots):
        args = [str(Path(bash).resolve()), bash_script_path(SCRIPTS / "security-check.sh")]
        # A current snapshot needs no network. A changed, stale or missing
        # snapshot must be replaced by a scan; failed scans remain blocked.
        gate = subprocess.run([*args, "gate", str(target)], cwd=target,
                              capture_output=True, text=True, timeout=30, check=False)
        if os.environ.get("VS_HOOK_LOCAL_ONLY") == "1":
            sys.stdout.write(gate.stdout)
            sys.stderr.write(gate.stderr)
            if gate.returncode:
                raise ValueError("local security evidence is missing, stale or changed; run an explicit security audit for current findings")
            continue
        if gate.returncode:
            result = subprocess.run([*args, "audit", str(target)], cwd=target,
                                    timeout=120, check=False)
            if result.returncode:
                raise ValueError("security scan failed after npm project changes; dependency work remains blocked")


if __name__ == "__main__":
    try:
        main()
    except (ValueError, OSError, subprocess.SubprocessError) as error:
        print(f"BLOCKED: version-sentinel. {error}", file=sys.stderr)
        sys.exit(2)
