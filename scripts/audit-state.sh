#!/usr/bin/env bash
# Internal project-state interface. Gates return 2 on failure.
set -u
DIR="${BASH_SOURCE[0]%/*}"
if ! command -v python3 >/dev/null 2>&1; then
  echo 'BLOCKED: version-sentinel. Python 3.11+ is required; dependency work cannot proceed.' >&2
  exit 2
fi
if ! python3 -c 'import tomllib' >/dev/null 2>&1; then
  echo 'BLOCKED: version-sentinel. Python 3.11+ with tomllib is required.' >&2
  exit 2
fi
if [[ "${1:-}" == gate || "${1:-}" == covers ]]; then
  for prerequisite in jq curl; do
    if ! command -v "$prerequisite" >/dev/null 2>&1; then
      echo "BLOCKED: version-sentinel. $prerequisite missing; dependency work cannot proceed." >&2
      exit 2
    fi
  done
fi
# MSYS can leave /tmp paths containing apostrophes unconverted in native argv.
# Map the Python entrypoint explicitly; the Python helper maps data paths.
python_entrypoint="$DIR/lib/project-state.py"
if command -v cygpath >/dev/null 2>&1; then
  if ! python_entrypoint=$(cygpath -C UTF8 -a -m -- "$python_entrypoint"); then
    echo 'BLOCKED: version-sentinel. Cannot map the audit helper path for native Python.' >&2
    exit 2
  fi
  python_entrypoint="${python_entrypoint%$'\r'}"
  if [[ -z "$python_entrypoint" || "$python_entrypoint" == *$'\n'* || "$python_entrypoint" == *$'\r'* ]]; then
    echo 'BLOCKED: version-sentinel. Invalid mapped audit helper path for native Python.' >&2
    exit 2
  fi
fi
exec python3 "$python_entrypoint" "$@"
