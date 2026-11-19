#!/usr/bin/env python3
"""Rescan changed npm state after supported mutation tools; never record checks."""
import importlib.util
import json
import os
from pathlib import Path
import re
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
        if not isinstance(data, dict):
            raise ValueError("PostToolUse command input must be an object")
        overrides = [data[k] for k in ("workdir", "dir_path", "cwd") if data.get(k) is not None]
        if any(not isinstance(v, str) for v in overrides) or len(set(overrides)) > 1:
            raise ValueError("conflicting PostToolUse command directories")
        if overrides:
            root = resolve_path(overrides[0], root)
        command = data.get("command", data.get("cmd", ""))
        if not isinstance(command, str):
            raise ValueError("PostToolUse command must be text")
        # Reuse the same conservative literal-directory parser as PreToolUse.
        spec = importlib.util.spec_from_file_location("install_context", SCRIPTS / "lib/install-context.py")
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        # Shell programs can write locks without naming a package manager.
        # Inspect the current root snapshot after every shell tool; a current
        # snapshot (or a project without npm files) performs no network request.
        roots.add(root)
        try:
            contexts = module.contexts(str(root), command)
        except ValueError:
            # PreToolUse rejects unsupported dependency commands. After a tool
            # has run we inspect actual files instead of interpreting shell
            # syntax or treating a heredoc's package text as an installation.
            contexts = []
        for context in contexts:
            if any(Path(p).name == "package.json" for p in context["required"]):
                roots.add(resolve_path(context["root"]))
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
