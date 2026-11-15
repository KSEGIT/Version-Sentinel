#!/usr/bin/env bash
# Record user-attested consent only. Never reconstruct manifest contents.
set -u
DIR="${BASH_SOURCE[0]%/*}"
if [[ $# -ne 4 || "$1" != approve || "$3" != --user-confirmed || -z "${4// /}" ]]; then
  echo 'BLOCKED: version-sentinel. Ask Daniel before recreating/repairing a manifest. After consent: bash scripts/recover-manifest.sh approve FILE --user-confirmed REASON' >&2
  exit 2
fi
exec bash "$DIR/audit-state.sh" approve "$PWD" "$2" "$3" "$4"
