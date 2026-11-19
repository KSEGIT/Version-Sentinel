#!/usr/bin/env bash
# Public hook entrypoint: all validation is advisory, including runtime errors.
DIR="${BASH_SOURCE[0]%/*}"
export VS_HOOK_LOCAL_ONLY=1
case "${VS_DISABLE:-${CLAUDE_PLUGIN_OPTION_DISABLE:-0}}" in 1|true|TRUE|True) exit 0 ;; esac
if source "$DIR/lib/advisory-hook.sh"; then
  vs_advisory_hook "$DIR/validate-detect-manifest-edit.sh" 'manifest edit' "$@"
else
  printf '%s\n' '{"systemMessage":"WARNING: Version Sentinel hook is unavailable. Work may continue."}'
fi
exit 0
