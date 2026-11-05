#!/usr/bin/env bash
VS_TEST_NAME=copilot-startup
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/tests/assert.sh"
VS_TMPDIR=$(mktemp -d)
trap 'rm -rf "$VS_TMPDIR"' EXIT
mkdir -p "$VS_TMPDIR/project"
cp -R "$ROOT/scripts" "$VS_TMPDIR/project/"
cd "$VS_TMPDIR/project" || exit 1
printf '{}' > package.json

# Execute the published repository hook so missing platform wiring also fails.
command=$(jq -r '.hooks.SessionStart[0].command' "$ROOT/.github/hooks/version-sentinel.json")
input=$(jq -nc --arg cwd "$PWD" '{cwd:$cwd,session_id:"copilot-session",hook_event_name:"SessionStart",source:"startup"}')
output=$(printf '%s' "$input" | bash -c "$command" 2>"$VS_TMPDIR/startup.err"); status=$?
assert_exit_code 0 "$status" "configured Copilot startup completes audit"
printf '%s' "$output" | jq -e 'type == "object" and (.additionalContext | type == "string" and contains("audit completed"))' >/dev/null 2>&1
assert_exit_code 0 "$?" "Copilot success returns JSON with top-level context"
VS_SESSION_ID=copilot-session bash "$ROOT/scripts/audit-state.sh" gate "$PWD" >/dev/null 2>&1
assert_exit_code 0 "$?" "Copilot success creates enforced session evidence"

printf '%s\n' '-r other.txt' > requirements.txt
output=$(printf '%s' "$input" | bash -c "$command" 2>"$VS_TMPDIR/startup.err"); status=$?
assert_exit_code 0 "$status" "configured Copilot blocked audit is advisory"
printf '%s' "$output" | jq -e 'type == "object" and (.additionalContext | type == "string" and contains("dependency work remains blocked") and (contains("audit completed") | not))' >/dev/null 2>&1
assert_exit_code 0 "$?" "Copilot blocked audit returns JSON with top-level failure context"
context=$(printf '%s' "$output" | jq -r '.additionalContext' 2>/dev/null)
assert_contains "$context" 'BLOCKED: version-sentinel. unsupported requirements include name: other.txt; use requirements*.txt or constraints*.txt' "Copilot preserves full audit diagnostic"
assert_contains "$context" "Resolve the reported errors, then rerun from" "Copilot includes retry guidance"
assert_contains "$context" "$PWD/scripts/check-versions.sh" "Copilot gives runnable audit path"
assert_eq pending "$(jq -r '.status' .version-sentinel/audit.json)" "Copilot blocked audit leaves evidence pending"
VS_SESSION_ID=copilot-session bash "$ROOT/scripts/audit-state.sh" gate "$PWD" >/dev/null 2>&1
assert_exit_code 2 "$?" "Copilot advisory failure revokes successful evidence"
bash "$ROOT/scripts/check-versions.sh" >/dev/null 2>&1
assert_exit_code 2 "$?" "direct audit remains blocked after Copilot advisory failure"
finish_test
