#!/usr/bin/env bash
# Explicit, guarded reconciliation of an existing lock after an approved edit.
set -u
DIR="$(cd "${BASH_SOURCE[0]%/*}" && pwd)"
source "$DIR/lib/options.sh"
python_entrypoint="$DIR/lib/npm_reconcile.py"
if command -v cygpath >/dev/null 2>&1; then
  python_entrypoint=$(cygpath -C UTF8 -a -m -- "$python_entrypoint") || exit 2
  python_entrypoint="${python_entrypoint%$'\r'}"
fi
exec python3 "$python_entrypoint" "$@"
