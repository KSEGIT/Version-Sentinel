#!/usr/bin/env bash
# Called from PostToolUse:Bash. Reads hook JSON on stdin.
# If the tool call was a successful install command, auto-insert a sidecar
# entry tagged "auto-recorded: post-install" for each recognized package.
# Must never fail the tool call. Exit 0 always.
set -u

DIR="$(dirname "$0")"
# shellcheck source=lib/options.sh
source "$DIR/lib/options.sh"
# shellcheck source=lib/platform.sh
source "$DIR/lib/platform.sh"

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
tool_name=$(normalize_tool_name "$tool_name")
if [[ "$tool_name" != "Bash" ]]; then
  exit 0
fi

cmd=$(echo "$input" | jq -r '.tool_input.command // empty')

# A multi-line command's later lines are usually DATA, not commands: heredoc
# bodies, generated scripts, commit messages. parse_install_cmd splits on
# newlines, so such a line is seen as an install and would be recorded even
# though nothing was installed -- and a recorded check switches the guard off
# for that package. Recording is the dangerous direction (see the header of
# lib/parse-install-cmd.sh), so decline rather than guess. The BLOCKING path is
# unaffected and still inspects every line.
case "$cmd" in
  *$'\n'*) exit 0 ;;
esac
[[ -z "$cmd" ]] && exit 0

# Refuse compound commands. The outer Bash exit code reflects only the last
# segment, so `npm install foo@1.2.3 || true` reports success even when the
# install actually failed. Auto-recording in that case would be a false
# positive — the user should /vs-record explicitly for anything non-trivial.
case "$cmd" in
  *"||"*|*"&&"*|*";"*|*"|"*|*'`'*|*'$('*)
    exit 0 ;;
esac

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

# Strict: no prefix stripping. See the header of lib/parse-install-cmd.sh --
# a fabricated record here turns the guard OFF for that package.
matches=$(parse_install_cmd_strict "$cmd")
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
