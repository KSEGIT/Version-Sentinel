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
exec python3 "$DIR/lib/project-state.py" "$@"
