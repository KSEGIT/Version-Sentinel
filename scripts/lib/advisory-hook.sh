#!/usr/bin/env bash
# Strict validators remain useful for CLI/CI; hook output has no denial authority.
vs_advisory_message() {
  local warning="$1" mode="${2:-}"
  if command -v python3 >/dev/null 2>&1; then
    if python3 - "$warning" "$mode" <<'PY'
import json
import sys
message, mode = sys.argv[1:]
result = {"systemMessage": message}
if mode != "--gemini":
    result["additionalContext"] = message
    result["hookSpecificOutput"] = {"hookEventName": "PreToolUse", "additionalContext": message}
print(json.dumps(result))
PY
    then return 0; fi
  fi
  # No external prerequisite is needed for the safe, visible fallback.
  printf '%s\n' '{"systemMessage":"WARNING: Version Sentinel verification is unavailable. Work may continue."}'
}

vs_advisory_hook() {
  local validator="$1" label="$2" output status warning line reason='' error_file diagnostics mode
  shift 2
  mode="${1:-}"
  error_file=$(mktemp 2>/dev/null) || {
    vs_advisory_message 'WARNING: Version Sentinel could not prepare verification. Work may continue.' "$mode"
    return 0
  }
  output=$(bash "$validator" "$@" 2>"$error_file")
  status=$?
  diagnostics=$(<"$error_file")
  rm -f "$error_file"
  # Successful local validators are silent. Never forward arbitrary stdout:
  # even an accidental success response must not control the host lifecycle.
  if [[ -n "$output" ]]; then status=2; fi
  if [[ "$status" -ne 0 ]]; then
    # Keep one concrete cause, without strict retry or consent instructions.
    while IFS= read -r line; do
      case "$line" in
        'BLOCKED: version-sentinel. '*)
          reason="${line#BLOCKED: version-sentinel. }"
          reason="${reason%%. *}"
          reason="${reason%%;*}"
          reason="${reason/Required dependency/Dependency}"
          case "$reason" in
            *blocked*|*before*|*consent*|*Ask*|*REQUIRED*|*deny*) reason='' ;;
          esac
          [[ -n "$reason" ]] && break
          ;;
      esac
    done <<< "$diagnostics"
    warning="WARNING: Version Sentinel could not verify the $label. Work may continue. Run check-versions.sh for audit details or vs-record.sh to record an online version check."
    if [[ -n "$reason" ]]; then
      warning="WARNING: Version Sentinel: $reason. Work may continue. Run check-versions.sh for audit details or vs-record.sh to record an online version check."
    fi
    vs_advisory_message "$warning" "$mode"
  fi
  return 0
}
