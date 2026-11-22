#!/usr/bin/env bash
# Keep the caller's working directory and the audit's streams and exit status.
DIR="$(cd "$(dirname "$0")" && pwd)" || exit $?
exec bash "$DIR/check-versions.sh" --report-evidence
