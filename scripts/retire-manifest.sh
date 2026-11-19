#!/usr/bin/env bash
# Retire one missing manifest only after consent and verified Git deletion.
set -u
DIR="${BASH_SOURCE[0]%/*}"
if [[ $# -ne 5 || "$2" != --deleted-by || "$4" != --user-confirmed ]]; then
  echo 'BLOCKED: version-sentinel. Ask Daniel first. After consent: bash scripts/retire-manifest.sh FILE --deleted-by COMMIT --user-confirmed REASON' >&2
  exit 2
fi
exec bash "$DIR/audit-state.sh" retire "$PWD" "$@"
