#!/usr/bin/env bash
# Startup audit may fail without preventing file inspection or user questions.
# PreToolUse gates enforce the failed/missing evidence for dependency work.
set -u
DIR="$(cd "${BASH_SOURCE[0]%/*}" && pwd)"
source "$DIR/lib/options.sh"
if [[ "${VS_DISABLE:-0}" == 1 ]]; then exit 0; fi
bash "$DIR/audit-state.sh" invalidate "$PWD" || exit 2
for prerequisite in jq curl python3; do
  if ! command -v "$prerequisite" >/dev/null 2>&1; then
    echo "BLOCKED: version-sentinel. $prerequisite missing; install prerequisites and rerun check-versions.sh. Dependency work is blocked; file inspection remains available." >&2
    exit 2
  fi
done
input=$(cat)
if [[ -n "$input" ]]; then
  if ! printf '%s' "$input" | jq -e 'type == "object" and ((.cwd // "")|type == "string") and ((.session_id // "")|type == "string")' >/dev/null 2>&1; then
    echo 'BLOCKED: version-sentinel. Invalid startup payload; mandatory audit was not completed.' >&2
    exit 2
  fi
  root=$(printf '%s' "$input" | jq -r '.cwd // empty')
  export VS_SESSION_ID
  VS_SESSION_ID=$(printf '%s' "$input" | jq -r '.session_id // empty')
  if [[ -n "$root" ]]; then cd "$root" || exit 2; fi
fi
bash "$DIR/audit-state.sh" invalidate "$PWD" || exit 2
exec bash "$DIR/check-versions.sh"
