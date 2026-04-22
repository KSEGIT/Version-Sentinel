#!/usr/bin/env bash
# Called from PostToolUse:Bash. Reads hook JSON on stdin.
# If the tool call was a successful install command, auto-insert a sidecar
# entry tagged "auto-recorded: post-install" for each recognized package.
# Must never fail the tool call. Exit 0 always.
set -u

DIR="$(dirname "$0")"
# shellcheck source=lib/options.sh
source "$DIR/lib/options.sh"

if [[ "${VS_DISABLE:-0}" == "1" ]]; then
  exit 0
fi

if ! command -v jq >/dev/null 2>&1; then
  exit 0
fi

input=$(cat)
if [[ -z "$input" ]]; then
  exit 0
fi
if ! echo "$input" | jq -e . >/dev/null 2>&1; then
  exit 0
fi

tool_name=$(echo "$input" | jq -r '.tool_name // empty')
if [[ "$tool_name" != "Bash" ]]; then
  exit 0
fi

cmd=$(echo "$input" | jq -r '.tool_input.command // empty')
[[ -z "$cmd" ]] && exit 0

# Skip failed installs. exit_code may be missing — assume success when absent.
exit_code=$(echo "$input" | jq -r '.tool_response.exit_code // empty')
if [[ -n "$exit_code" && "$exit_code" != "0" ]]; then
  exit 0
fi
# Some runners report .tool_response.success instead.
success=$(echo "$input" | jq -r '.tool_response.success // empty')
if [[ -n "$success" && "$success" != "true" ]]; then
  exit 0
fi

# shellcheck source=lib/parse-install-cmd.sh
source "$DIR/lib/parse-install-cmd.sh"
# shellcheck source=lib/sidecar.sh
source "$DIR/lib/sidecar.sh"

matches=$(parse_install_cmd "$cmd")
[[ -z "$matches" ]] && exit 0

path=$(sidecar_path "$PWD")
while IFS=$'\t' read -r eco pkg ver; do
  [[ -z "$pkg" ]] && continue
  [[ -z "$ver" ]] && continue
  if sidecar_write_entry "$path" "$eco" "$pkg" "$ver" "auto-recorded: post-install" 2>/dev/null; then
    echo "version-sentinel: auto-recorded $eco/$pkg@$ver" >&2
  fi
done <<< "$matches"

exit 0
