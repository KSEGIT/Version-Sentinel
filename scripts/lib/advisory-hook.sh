#!/usr/bin/env bash
# Strict validators remain useful for CLI/CI; hook output has no denial authority.
vs_action_hint() {
  printf ' (Claude/Kimi: /version-sentinel:%s; Codex: $version-sentinel:%s skill; Copilot CLI/Zed: %s skill)' "$1" "$1" "$1"
}

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

vs_warning_seen() {
  local validator="$1" payload_file="$2" helper="${BASH_SOURCE[0]%/*}/warning-history.py"
  shift 2
  command -v python3 >/dev/null 2>&1 || return 1
  if command -v cygpath >/dev/null 2>&1; then
    helper=$(cygpath -C UTF8 -a -m -- "$helper") || return 1
    helper="${helper%$'\r'}"
  fi
  # Send large findings on stdin, since argv has short per-argument limits.
  { printf '%s\0' "$@" | python3 "$helper" "${validator##*/}" "$payload_file"; } 2>/dev/null
}

vs_advisory_hook() {
  local validator="$1" label="$2" output status warning line reason='' error_file diagnostics mode
  local event=PreToolUse findings='' unexpected_output=0 scratch payload_file
  shift 2
  if [[ "${1:-}" == --event ]]; then
    event="${2:-PreToolUse}"
    shift 2
  fi
  mode="${1:-}"
  scratch=$(mktemp -d 2>/dev/null) || {
    vs_advisory_message 'WARNING: Version Sentinel could not prepare verification. Work may continue.' "$mode" "$event"
    return 0
  }
  payload_file="$scratch/input"
  error_file="$scratch/error"
  if ! cat 2>/dev/null >"$payload_file"; then
    rm -rf -- "$scratch"
    vs_advisory_message 'WARNING: Version Sentinel could not read verification input. Work may continue.' "$mode" "$event"
    return 0
  fi
  output=$(bash "$validator" "$@" <"$payload_file" 2>"$error_file")
  status=$?
  diagnostics=$(<"$error_file")
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
    if [[ -n "$reason" ]]; then
      warning="WARNING: Version Sentinel: $reason. Work may continue."
    elif [[ "$status" -eq 0 ]]; then
      warning="WARNING: Version Sentinel reported security findings for the $label. Work may continue."
    else
      warning="WARNING: Version Sentinel could not verify the $label. Work may continue."
    fi
    if [[ "$status" -ne 0 || -n "$reason" ]]; then
      local candidate_diagnostic='local hook mode does not query advisory providers for proposed changes'
      local guidance='' current_audit=0
      while IFS= read -r line; do
        case "$line" in
          *'dependency audit'*|*'Dependency manifest'*|*'Required dependency manifest'*|*'Required manifest'*|*'required manifest'*|*'was not included in the successful audit'*|*'Security audit evidence missing'*|*'security evidence is missing'*)
            current_audit=1; break ;;
          *"$candidate_diagnostic"*) ;; # This unknown coverage applies to proposed changes.
          *'Security unknown/incomplete'*)
            current_audit=1; break ;;
        esac
      done <<< "$diagnostics"
      if [[ "$current_audit" -eq 1 ]]; then
        guidance+=" Use /vs-refresh for project audit and security evidence$(vs_action_hint vs-refresh)."
      fi
      if [[ "$diagnostics" == *"$candidate_diagnostic"* ]]; then
        guidance+=" Use /vs-refresh after dependency changes to audit the resolved tree$(vs_action_hint vs-refresh)."
      fi
      case "$diagnostics" in
        *'No fresh successful online version check'*|*'No explicit registry version was provided'*)
          guidance+=" Use /vs-record for an individual package check$(vs_action_hint vs-record)." ;;
      esac
      if [[ -z "$guidance" ]]; then
        guidance=" Use /vs-refresh for project audit and security evidence$(vs_action_hint vs-refresh), or /vs-record for an individual package check$(vs_action_hint vs-record)."
      fi
      warning+="$guidance"
    fi
    if [[ -n "$findings" ]]; then warning+=$'\n'"${findings%$'\n'}"; fi
    if ! vs_warning_seen "$validator" "$payload_file" "$output" "$diagnostics" "$warning"; then
      vs_advisory_message "$warning" "$mode" "$event"
    fi
  else
    vs_warning_seen "$validator" "$payload_file" '' '' '' || true
  fi
  rm -rf -- "$scratch"
  return 0
}
