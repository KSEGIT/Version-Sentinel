"""Paths at the native Python / Git Bash boundary.

MSYS mount names in JSON do not receive Git Bash's argv conversion. Ask its
path mapper instead of guessing that /tmp or /c is a native Windows path.
"""
import os
from pathlib import Path
import subprocess


def native_path_text(value):
    if not isinstance(value, str):
        raise ValueError("path must be text")
    if os.name == "nt" and value.startswith("/") and not value.startswith("//"):
        try:
            result = subprocess.run(["cygpath", "-C", "UTF8", "-w", "--", value], capture_output=True,
                                    text=True, encoding="utf-8", timeout=10, check=False)
        except (OSError, subprocess.SubprocessError) as error:
            raise ValueError("Cannot map Git Bash path; cygpath is required on Windows") from error
        converted = result.stdout.rstrip("\r\n")
        if result.returncode or not converted or "\n" in converted or "\r" in converted:
            raise ValueError("Cannot map Git Bash path to its native Windows location")
        return converted
    return value


def resolve_path(value, base=None):
    path = Path(native_path_text(value))
    return ((base / path) if base is not None else path).resolve()


def bash_script_path(path):
    # Native Python must not pass backslash-only script filenames to Bash:
    # BASH_SOURCE%/* and dirname require forward separators.
    return path.as_posix()


def relative_key(path, root):
    """Use one portable key shape for serialized manifest inventories."""
    return path.relative_to(root).as_posix()
