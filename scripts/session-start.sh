#!/usr/bin/env bash
# Keep startup local: slow registries must not delay the host lifecycle hook.
case "${VS_DISABLE:-${CLAUDE_PLUGIN_OPTION_DISABLE:-0}}" in 1|true|TRUE|True) exit 0 ;; esac
printf '%s\n' '{"systemMessage":"WARNING: Version Sentinel is advisory. Work may continue. An online dependency audit is optional: run check-versions.sh when useful.","additionalContext":"Version Sentinel checks are advisory. Work may continue. An online dependency audit is optional: run check-versions.sh when useful.","hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"Version Sentinel checks are advisory. Work may continue. An online dependency audit is optional: run check-versions.sh when useful."}}'
exit 0
