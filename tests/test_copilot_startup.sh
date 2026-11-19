#!/usr/bin/env bash
VS_TEST_NAME=copilot-startup
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/tests/assert.sh"
VS_TMPDIR=$(mktemp -d)
trap 'rm -rf "$VS_TMPDIR"' EXIT
cp -R "$ROOT/scripts" "$VS_TMPDIR/"
cd "$VS_TMPDIR" || exit 1
printf '%s\n' '-r other.txt' > requirements.txt
command=$(jq -r '.hooks.SessionStart[0].command' "$ROOT/.github/hooks/version-sentinel.json")
output=$(printf '{}' | bash -c "$command"); status=$?
assert_exit_code 0 "$status" 'configured Copilot startup continues'
printf '%s' "$output" | jq -e '.systemMessage and (.additionalContext | contains("optional")) and .hookSpecificOutput.hookEventName == "SessionStart"' >/dev/null
assert_exit_code 0 "$?" 'Copilot gives visible optional-audit context'
if [[ -d .version-sentinel ]]; then _fail 'startup must not write audit evidence'; fi
finish_test
