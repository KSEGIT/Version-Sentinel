#!/usr/bin/env bash
# Explicit post-change security validator; public hooks wrap its result.
set -u
DIR="$(cd "${BASH_SOURCE[0]%/*}" && pwd)"
source "$DIR/lib/options.sh"
if [[ "${VS_DISABLE:-0}" == 1 ]]; then exit 0; fi
if ! command -v python3 >/dev/null 2>&1; then
  echo 'BLOCKED: version-sentinel. python3 is required to check changed security state.' >&2
  exit 2
fi
python3 "$DIR/lib/security-post.py"
status=$?
[[ "$status" -eq 0 ]] || exit 2
