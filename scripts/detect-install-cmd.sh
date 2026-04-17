#!/usr/bin/env bash
set -u

if [[ "${VS_DISABLE:-0}" == "1" ]]; then exit 0; fi

DIR="$(dirname "$0")"
source "$DIR/lib/parse-install-cmd.sh"

input=$(cat)

if ! command -v jq >/dev/null 2>&1; then
  echo "version-sentinel: jq missing, fail-open" >&2; exit 0
fi
if ! echo "$input" | jq -e . >/dev/null 2>&1; then exit 0; fi

tool_name=$(echo "$input" | jq -r '.tool_name // empty')
[[ "$tool_name" != "Bash" ]] && exit 0

cmd=$(echo "$input" | jq -r '.tool_input.command // empty')
[[ -z "$cmd" ]] && exit 0

matches=$(parse_install_cmd "$cmd")
[[ -z "$matches" ]] && exit 0

block=0
block_msgs=""
while IFS=$'\t' read -r eco pkg ver; do
  [[ -z "$pkg" ]] && continue
  [[ -z "$ver" ]] && continue
  if ! bash "$DIR/check-sidecar.sh" "$eco" "$pkg" "$ver" 2>/tmp/_vs_err_$$; then
    block=1
    block_msgs+=$(cat /tmp/_vs_err_$$)$'\n---\n'
  fi
done <<< "$matches"
rm -f /tmp/_vs_err_$$

if [[ "$block" -eq 1 ]]; then
  echo "$block_msgs" >&2
  exit 2
fi
exit 0
