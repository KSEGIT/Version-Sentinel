#!/usr/bin/env bash
# The visible warning must provide a retry that works outside the project.
set -u
VS_TEST_NAME=startup-recovery-guidance
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/tests/assert.sh"
VS_TMPDIR=$(mktemp -d)
trap 'rm -rf "$VS_TMPDIR"' EXIT
source "$ROOT/tests/registry-fixture.sh"
registry_fixture_setup
export VS_REGISTRY_RETRY_DELAY=0
PLUGIN="$VS_TMPDIR/plugin's directory"
PROJECT="$VS_TMPDIR/project's directory"
mkdir -p "$PLUGIN" "$PROJECT" "$VS_TMPDIR/elsewhere"
cp -R "$ROOT/scripts" "$PLUGIN/"
PROJECT=$(cd "$PROJECT" && pwd -P)
printf '%s\n' '{"dependencies":{"lodash":"4.17.21"}}' > "$PROJECT/package.json"

for mode in '' --gemini --copilot; do
  input=$(jq -nc --arg cwd "$PROJECT" '{cwd:$cwd,session_id:"warning-session"}')
  output=$(printf '%s' "$input" | VS_FIXTURE_NETWORK_FAIL=1 bash "$PLUGIN/scripts/session-start.sh" "$mode" 2>"$VS_TMPDIR/startup.err"); status=$?
  assert_exit_code 0 "$status" "failed startup remains advisory ($mode)"
  printf '%s' "$output" | jq -e 'type == "object" and .hookSpecificOutput.hookEventName == "SessionStart"' >/dev/null 2>&1
  assert_exit_code 0 "$?" "failed startup returns JSON ($mode)"
  message=$(printf '%s' "$output" | jq -r '.systemMessage' | tr -d '\r')
  assert_contains "$message" 'dependency work remains blocked' "visible warning keeps enforcement status ($mode)"
  assert_contains "$message" 'audit-dependencies skill' "visible warning names audit skill ($mode)"
  retry=$(printf '%s\n' "$message" | tail -1)
  if [[ "$retry" != cd\ * ]]; then
    _fail "visible warning must end with a self-contained retry command ($mode): $message"
    continue
  fi
  result=$(cd "$VS_TMPDIR/elsewhere" && CODEX_THREAD_ID=warning-session VS_SESSION_ID= VS_FIXTURE_NETWORK_FAIL=1 bash -c "$retry" 2>&1); status=$?
  assert_exit_code 2 "$status" "visible retry still fails closed on registry failure ($mode)"
  assert_contains "$result" 'lookup-failed' "visible retry reaches intended project and installed audit ($mode)"
  VS_SESSION_ID=warning-session bash "$ROOT/scripts/audit-state.sh" gate "$PROJECT" >/dev/null 2>&1
  assert_exit_code 2 "$?" "failed retry keeps project gate closed ($mode)"
  result=$(cd "$VS_TMPDIR/elsewhere" && CODEX_THREAD_ID=warning-session VS_SESSION_ID= VS_FIXTURE_NETWORK_FAIL=0 bash -c "$retry" 2>&1); status=$?
  assert_exit_code 0 "$status" "visible retry handles spaces and apostrophes in both paths ($mode): $result"
  assert_contains "$result" 'mandatory online dependency audit completed' "visible retry reports completed audit ($mode)"
  VS_SESSION_ID=warning-session bash "$ROOT/scripts/audit-state.sh" gate "$PROJECT" >/dev/null 2>&1
  assert_exit_code 0 "$?" "successful visible retry creates current project evidence ($mode)"
done

finish_test
