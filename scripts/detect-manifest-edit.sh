#!/usr/bin/env bash
# All edit shapes share one parser, including Codex patch-only input.
set -u
DIR="${BASH_SOURCE[0]%/*}"
# shellcheck source=lib/options.sh
source "$DIR/lib/options.sh"
if [[ "${VS_DISABLE:-0}" == "1" ]]; then exit 0; fi
if ! command -v python3 >/dev/null 2>&1; then
  echo "BLOCKED: version-sentinel. python3 is required to inspect manifest edits." >&2
  exit 2
fi
python3 "$DIR/lib/manifest-edit.py"
