#!/usr/bin/env bash
# Strict validators remain useful for CLI/CI; hook output has no denial authority.
vs_advisory_message() {
  local warning="$1" mode="${2:-}" event="${3:-PreToolUse}"
  if command -v python3 >/dev/null 2>&1; then
    if printf '%s' "$warning" | python3 -c '
import json
import sys
mode, event = sys.argv[1:]
message = sys.stdin.read()
result = {"systemMessage": message}
if mode == "--copilot":
    result["additionalContext"] = message
if mode != "--gemini":
    result["hookSpecificOutput"] = {"hookEventName": event, "additionalContext": message}
print(json.dumps(result))
' "$mode" "$event"
    then return 0; fi
  fi
  # No external prerequisite is needed for the safe, visible fallback.
  printf '%s\n' '{"systemMessage":"WARNING: Version Sentinel verification is unavailable. Work may continue."}'
}

vs_advisory_hook() {
  local validator="$1" label="$2" output status warning line reason='' error_file diagnostics mode
  local event=PreToolUse findings='' unexpected_output=0
  shift 2
  if [[ "${1:-}" == --event ]]; then
    event="${2:-PreToolUse}"
    shift 2
  fi
  mode="${1:-}"
  error_file=$(mktemp 2>/dev/null) || {
    vs_advisory_message 'WARNING: Version Sentinel could not prepare verification. Work may continue.' "$mode" "$event"
    return 0
  }
  output=$(bash "$validator" "$@" 2>"$error_file")
  status=$?
  diagnostics=$(<"$error_file")
  rm -f "$error_file"
  # Findings are plain text inside our own JSON, never host lifecycle fields.
  # Ignore informational provider summaries, but warn on unexpected stdout.
  while IFS= read -r line; do
    case "$line" in
      ''|'security '*|'security: '*|'GHSA-'*|'CVE-'*) ;;
      *) unexpected_output=1 ;;
    esac
  done <<< "$output"
  while IFS= read -r line; do
    case "$line" in
      'security finding: '*|'security unknown/incomplete: '*|'GHSA-'*|'CVE-'*)
        findings+="$line"$'\n' ;;
    esac
  done <<< "$output"$'\n'"$diagnostics"
  if [[ "$unexpected_output" -eq 1 ]]; then status=2; fi
  if [[ "$status" -ne 0 || -n "$findings" ]]; then
    # Keep one concrete cause, without strict retry or consent instructions.
    while IFS= read -r line; do
      case "$line" in
        'BLOCKED: version-sentinel. '*)
          reason="${line#BLOCKED: version-sentinel. }"
          reason="${reason%%. *}"
          reason="${reason%%;*}"
          reason="${reason/Required dependency/Dependency}"
          case "$reason" in
            *blocked*|*BLOCKED*|*Blocked*|*before*|*consent*|*Ask*|*REQUIRED*|*deny*|*DENY*) reason='' ;;
          esac
          [[ -n "$reason" ]] && break
          ;;
      esac
    done <<< "$diagnostics"
    warning="WARNING: Version Sentinel could not verify the $label. Work may continue. Run check-versions.sh for audit details or vs-record.sh to record an online version check."
    if [[ "$status" -eq 0 ]]; then
      warning="WARNING: Version Sentinel reported security findings for the $label. Work may continue."
    fi
    if [[ -n "$reason" ]]; then
      warning="WARNING: Version Sentinel: $reason. Work may continue. Run check-versions.sh for audit details or vs-record.sh to record an online version check."
    fi
    if [[ -n "$findings" ]]; then warning+=$'\n'"${findings%$'\n'}"; fi
    vs_advisory_message "$warning" "$mode" "$event"
  fi
  return 0
}
