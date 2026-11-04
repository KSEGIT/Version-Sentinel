#!/usr/bin/env bash
VS_TEST_NAME=gemini-startup
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/tests/assert.sh"
VS_TMPDIR=$(mktemp -d)
trap 'rm -rf "$VS_TMPDIR"' EXIT
mkdir -p "$VS_TMPDIR/project"
cd "$VS_TMPDIR/project" || exit 1
printf '{}' > package.json
for source in startup resume clear; do
  output=$(jq -nc --arg cwd "$PWD" --arg source "$source" '{cwd:$cwd,source:$source,session_id:$source,hook_event_name:"SessionStart"}' |
    bash "$ROOT/scripts/session-start.sh" --gemini 2>"$VS_TMPDIR/startup.err"); status=$?
  assert_exit_code 0 "$status" "Gemini $source runs audit"
  printf '%s' "$output" | jq -e 'type == "object" and (.hookSpecificOutput.additionalContext | contains("audit completed"))' >/dev/null 2>&1
  assert_exit_code 0 "$?" "Gemini $source returns valid JSON context"
  VS_SESSION_ID="$source" bash "$ROOT/scripts/audit-state.sh" gate "$PWD" >/dev/null 2>&1
  assert_exit_code 0 "$?" "Gemini $source creates enforced session evidence"
done
# The published Gemini schema uses milliseconds, not seconds.
timeout=$(jq '.hooks.SessionStart[0].hooks[0].timeout' "$ROOT/hooks/gemini-hooks.json")
if [[ "$timeout" -lt 60000 ]]; then _fail 'Gemini startup timeout must allow a real online audit (milliseconds)'; fi
matcher=$(jq -r '.hooks.SessionStart[0].matcher // ""' "$ROOT/hooks/gemini-hooks.json")
assert_eq '' "$matcher" 'Gemini startup audit covers resume and clear too'
finish_test
