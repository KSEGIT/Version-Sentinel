#!/usr/bin/env bash
# Keep startup local: slow registries must not delay the host lifecycle hook.
case "${VS_DISABLE:-${CLAUDE_PLUGIN_OPTION_DISABLE:-0}}" in 1|true|TRUE|True) exit 0 ;; esac
# Copilot also reads root context; other hosts use event-specific context.
if [[ "${1:-}" == --copilot ]]; then
  printf '%s\n' '{"systemMessage":"WARNING: Version Sentinel is advisory. Work may continue. An online dependency audit is optional: run check-versions.sh when useful.","additionalContext":"Version Sentinel checks are advisory. Work may continue. An online dependency audit is optional: run check-versions.sh when useful.","hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"Version Sentinel checks are advisory. Work may continue. An online dependency audit is optional: run check-versions.sh when useful."}}'
else
  printf '%s\n' '{"systemMessage":"WARNING: Version Sentinel is advisory. Work may continue. An online dependency audit is optional: run check-versions.sh when useful.","hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"Version Sentinel checks are advisory. Work may continue. An online dependency audit is optional: run check-versions.sh when useful."}}'
fi
exit 0
