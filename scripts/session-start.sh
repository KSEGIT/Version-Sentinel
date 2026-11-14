#!/usr/bin/env bash
# Startup audit may fail without preventing file inspection or user questions.
# PreToolUse gates enforce the failed/missing evidence for dependency work.
set -u
DIR="$(cd "${BASH_SOURCE[0]%/*}" && pwd)"
source "$DIR/lib/options.sh"
if [[ "${VS_DISABLE:-0}" == 1 ]]; then exit 0; fi
# Python selects the payload project and revokes evidence before jq/curl checks.
input=$(cat)
context=$(printf '%s' "$input" | bash "$DIR/audit-state.sh" startup-invalidate "$PWD") || exit 2
for prerequisite in jq curl python3; do
  if ! command -v "$prerequisite" >/dev/null 2>&1; then
    echo "BLOCKED: version-sentinel. $prerequisite missing; install prerequisites and rerun check-versions.sh. Dependency work is blocked; file inspection remains available." >&2
    exit 2
  fi
done
root=$(printf '%s' "$context" | vs_jq -r '.cwd') || exit 2
export VS_SESSION_ID
VS_SESSION_ID=$(printf '%s' "$context" | vs_jq -r '.session_id') || exit 2
cd "$root" || exit 2
audit_output=$(bash "$DIR/check-versions.sh" --startup 2>&1)
audit_status=$?
if [[ "$audit_status" -eq 2 && "$audit_output" == *'BLOCKED: version-sentinel.'* ]]; then
  # A reported audit block is context, not a lifecycle hook crash. The audit
  # already revoked prior evidence; PreToolUse still blocks dependency work.
  warning='Version Sentinel startup audit failed; dependency work remains blocked. File inspection and questions remain available.'
  printf -v retry 'Resolve the reported errors, then rerun from %q: bash %q' "$PWD" "$DIR/check-versions.sh"
  printf '%s\n' "$audit_output" >&2
  printf '%s\n\n%s\n%s\n' "$audit_output" "$warning" "$retry" |
    if [[ "${1:-}" == --copilot ]]; then
      vs_jq -Rs --arg warning "$warning" '{systemMessage:$warning,additionalContext:.,hookSpecificOutput:{hookEventName:"SessionStart",additionalContext:.}}'
    else
      vs_jq -Rs --arg warning "$warning" '{systemMessage:$warning,hookSpecificOutput:{hookEventName:"SessionStart",additionalContext:.}}'
    fi
  exit "$?"
fi
if [[ "$audit_status" -ne 0 ]]; then
  # Setup errors and unexpected audit crashes remain failures, with diagnostics.
  printf '%s\n' "$audit_output" >&2
  exit "$audit_status"
fi
# An empty startup inventory has no audit result or context to report.
if [[ -z "$audit_output" ]]; then exit 0; fi
if [[ "${1:-}" == --gemini ]]; then
  # Gemini permits JSON only on stdout, including for a blocked audit above.
  printf '%s\n' "$audit_output" >&2
  printf '%s' "$audit_output" | vs_jq -Rs '{hookSpecificOutput:{hookEventName:"SessionStart",additionalContext:.}}'
elif [[ "${1:-}" == --copilot ]]; then
  printf '%s\n' "$audit_output" >&2
  printf '%s' "$audit_output" | vs_jq -Rs '{additionalContext:.,hookSpecificOutput:{hookEventName:"SessionStart",additionalContext:.}}'
else
  printf '%s\n' "$audit_output"
fi
