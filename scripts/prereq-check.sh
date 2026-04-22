#!/usr/bin/env bash
# Check that jq, curl, python3 are on PATH. Warn (non-blocking) if any missing.
# Called from SessionStart hook — must never block a session. Exit 0 always.
set -u

DIR="$(dirname "$0")"
# shellcheck source=lib/options.sh
source "$DIR/lib/options.sh"

if [[ "${VS_DISABLE:-0}" == "1" ]]; then
  exit 0
fi

_warn_missing() {
  local tool="$1" hint="$2"
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "version-sentinel: $tool not found on PATH. Install: $hint" >&2
  fi
}

_warn_missing "jq"      "https://stedolan.github.io/jq/download/ (apt install jq | brew install jq | bundled with Git Bash on Windows)"
_warn_missing "curl"    "usually bundled; on minimal containers: apt install curl"
_warn_missing "python3" "Python 3.11+ required for tomllib (pyproject.toml). https://www.python.org/downloads/"

exit 0
