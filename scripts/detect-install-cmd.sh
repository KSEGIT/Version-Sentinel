#!/usr/bin/env bash
set -u

DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/options.sh
source "$DIR/lib/options.sh"
# shellcheck source=lib/platform.sh
source "$DIR/lib/platform.sh"

if [[ "${VS_DISABLE:-0}" == "1" ]]; then exit 0; fi

# shellcheck source=lib/parse-install-cmd.sh
source "$DIR/lib/parse-install-cmd.sh"

input=$(cat)

if ! command -v jq >/dev/null 2>&1; then
  echo "BLOCKED: version-sentinel. jq missing; install prerequisites before dependency work." >&2; exit 2
fi
if ! echo "$input" | vs_jq -e 'type == "object"' >/dev/null 2>&1; then
  echo "BLOCKED: version-sentinel. Malformed hook JSON; cannot inspect dependency command." >&2; exit 2
fi

tool_name=$(echo "$input" | vs_jq -er '.tool_name | select(type == "string")') || {
  echo "BLOCKED: version-sentinel. Missing or malformed tool_name." >&2; exit 2;
}
tool_name=$(normalize_tool_name "$tool_name")
[[ "$tool_name" != "Bash" ]] && exit 0

cmd=$(echo "$input" | vs_jq -er '.tool_input.command // .tool_input.cmd | select(type == "string")') || {
  echo "BLOCKED: version-sentinel. Missing or malformed shell command." >&2; exit 2;
}
[[ -z "$cmd" ]] && exit 0


unpinned_install_message() {
  local eco="$1" pkg="$2" retry
  case "$eco" in
    npm) retry="npm install $pkg@<version>" ;;
    pip) retry="pip install $pkg==<version>" ;;
    cargo) retry="cargo add $pkg@<version>" ;;
    csproj) retry="dotnet add package $pkg --version <version>" ;;
    *) retry="install $pkg at <version>" ;;
  esac
  cat <<EOF
BLOCKED: version-sentinel.
Package: $pkg ($eco).
No explicit registry version was provided. Floating tags and omitted versions cannot be recorded as an exact version check.

REQUIRED before retry:
1. Look up the current version of "$pkg" on the $eco registry.
2. Record that exact version and the source URL with /vs-record.
3. Retry with an explicit version: $retry
EOF
}

check_matches() {
local check_root="$1" matches="$2"
local block=0 block_msgs=""
local err_file
err_file=$(mktemp) || return 2
while IFS=$'\t' read -r eco pkg ver; do
  if [[ "$eco" == "$VS_PARSE_AMBIGUOUS_ECOSYSTEM" ]]; then
    block=1
    block_msgs+="BLOCKED: version-sentinel."$'\n'"Cannot safely inspect command: $pkg."$'\n---\n'
    continue
  fi
  [[ -z "$pkg" ]] && continue
  if [[ "$ver" == "$VS_UNPINNED_VERSION" ]]; then
    block=1
    block_msgs+=$(unpinned_install_message "$eco" "$pkg")$'\n---\n'
    continue
  fi
  [[ -z "$ver" ]] && continue
  if ! (cd "$check_root" && bash "$DIR/check-sidecar.sh" "$eco" "$pkg" "$ver") 2>"$err_file"; then
    block=1
    block_msgs+=$(cat "$err_file")$'\n---\n'
  fi
done <<< "$matches"
rm -f "$err_file"

if [[ "$block" -eq 1 ]]; then
  echo "$block_msgs" >&2
  return 2
fi
return 0
}

# Resolve the actual command project, including Codex workdir and literal cd.
if ! command -v python3 >/dev/null 2>&1; then
  echo "BLOCKED: version-sentinel. Python 3.11+ is required to inspect dependency commands." >&2; exit 2
fi
project_root=$(printf '%s' "$input" | python3 "$DIR/lib/install-context.py" --payload-root) || exit 2
contexts=$(python3 "$DIR/lib/install-context.py" "$project_root" "$cmd") || exit 2
# Keep session-bound startup evidence usable across the platform's payloads.
VS_SESSION_ID=$(echo "$input" | vs_jq -r '.session_id // empty')
export VS_SESSION_ID
context_count=$(echo "$contexts" | vs_jq 'length') || exit 2
if [[ ! "$context_count" =~ ^[0-9]+$ ]]; then
  echo "BLOCKED: version-sentinel. Cannot read dependency command contexts." >&2; exit 2
fi
context_index=0
while [[ "$context_index" -lt "$context_count" ]]; do
  context=$(echo "$contexts" | vs_jq -c ".[${context_index}]")
  target_root=$(echo "$context" | vs_jq -r '.root')
  bash "$DIR/audit-state.sh" gate "$target_root" || exit 2
  while IFS= read -r required; do
    [[ -z "$required" ]] && continue
    if [[ ! -f "$required" ]]; then
      echo "BLOCKED: version-sentinel. Required manifest is missing: $required. Ask Daniel before recreating it. Use user-confirmed recovery, verify proposed dependencies, then rerun the audit." >&2
      exit 2
    fi
    bash "$DIR/audit-state.sh" covers "$target_root" "$required" || exit 2
  done <<< "$(echo "$context" | vs_jq -r '.required[]')"
  # Every recognized package in this context must have its own online check.
  normalized_cmd=$(echo "$context" | vs_jq -r '.command')
  matches=$(parse_install_cmd "$normalized_cmd")
  if [[ -n "$matches" ]]; then
    check_matches "$target_root" "$matches" || exit 2
  fi
  context_index=$((context_index + 1))
done
# Legacy parser catches additional conservative forms such as env -S. It must
# not allow a recognized addition merely because context recovery failed.
if [[ "$context_count" -eq 0 ]]; then
  matches=$(parse_install_cmd "$cmd")
  [[ -z "$matches" ]] && exit 0
  bash "$DIR/audit-state.sh" gate "$project_root" || exit 2
  check_matches "$project_root" "$matches" || exit 2
fi
exit 0
