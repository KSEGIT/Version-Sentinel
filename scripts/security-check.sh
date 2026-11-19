#!/usr/bin/env bash
# Read-only npm advisory audit, evidence gate, or proposed exact-version check.
set -u
DIR="$(cd "${BASH_SOURCE[0]%/*}" && pwd)"
source "$DIR/lib/options.sh"
if [[ "${VS_DISABLE:-0}" == 1 ]]; then exit 0; fi
if ! command -v python3 >/dev/null 2>&1; then
  echo 'BLOCKED: version-sentinel. Security unknown/incomplete: Python 3.11+ is required.' >&2
  exit 2
fi
python_entrypoint="$DIR/lib/security-settings.py"
if [[ "${VS_HOOK_LOCAL_ONLY:-0}" == 1 ]]; then
  # Public hooks inspect cached evidence only. They must not launch Claude's
  # settings CLI, contact advisory providers, or create new scan evidence.
  python_entrypoint="$DIR/lib/security.py"
  if [[ "${1:-}" == audit ]]; then
    shift
    set -- gate "$@"
  fi
fi
if command -v cygpath >/dev/null 2>&1; then
  python_entrypoint=$(cygpath -C UTF8 -a -m -- "$python_entrypoint") || exit 2
  python_entrypoint="${python_entrypoint%$'\r'}"
fi
exec python3 "$python_entrypoint" "$@"
