#!/usr/bin/env bash
# A manual Codex audit must authorize the matching real hook, not another session.
VS_TEST_NAME=manual-audit-session
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/tests/assert.sh"
source "$ROOT/tests/registry-fixture.sh"
VS_TMPDIR=$(mktemp -d)
trap 'rm -rf "$VS_TMPDIR"' EXIT
unset VS_SESSION_ID CODEX_THREAD_ID
registry_fixture_setup
mkdir -p "$VS_TMPDIR/launch" "$VS_TMPDIR/project" "$VS_TMPDIR/other"
printf '%s\n' '{"overrides":{"postcss":"$postcss","sharp":"^0.35.4"}}' > "$VS_TMPDIR/launch/package.json"
cp "$VS_TMPDIR/launch/package.json" "$VS_TMPDIR/launch-original.json"
printf '%s\n' '{"dependencies":{"lodash":"4.17.21"}}' > "$VS_TMPDIR/project/package.json"
printf '%s\n' '{}' > "$VS_TMPDIR/other/package.json"
cd "$VS_TMPDIR/project" || exit 1

hook() {
  jq -nc --arg cwd "$VS_TMPDIR/launch" --arg workdir "${2:-$PWD}" --arg session "$1" \
    '{tool_name:"exec_command",cwd:$cwd,session_id:$session,tool_input:{cmd:"npm run verify",workdir:$workdir}}' |
    CODEX_THREAD_ID=unrelated-hook-environment bash "$ROOT/scripts/validate-detect-install-cmd.sh" 2>&1
}

# A fresh explicit workdir has no startup identity to inherit.
CODEX_THREAD_ID=manual-one bash "$ROOT/scripts/check-versions.sh" >/dev/null 2>&1
assert_exit_code 0 "$?" 'manual audit succeeds without an explicit VS_SESSION_ID'
assert_eq manual-one "$(jq -r .session .version-sentinel/audit.json)" 'manual audit detects the Codex thread'
output=$(hook manual-one); status=$?
assert_exit_code 0 "$status" "matching hook accepts cmd/workdir from unrelated cwd ($output)"
output=$(hook manual-two); status=$?
assert_exit_code 2 "$status" 'another session cannot reuse the manual audit'
output=$(hook manual-one "$VS_TMPDIR/other"); status=$?
assert_exit_code 2 "$status" 'another project cannot reuse the manual audit'

# Current host identity wins over a previously recorded session.
CODEX_THREAD_ID=manual-two bash "$ROOT/scripts/check-versions.sh" >/dev/null 2>&1
assert_exit_code 0 "$?" 'new Codex session can complete a fresh audit'
assert_eq manual-two "$(jq -r .session .version-sentinel/audit.json)" 'current Codex session replaces previous evidence identity'
output=$(hook manual-two); status=$?
assert_exit_code 0 "$status" "new session hook accepts its fresh audit ($output)"
output=$(hook manual-one); status=$?
assert_exit_code 2 "$status" 'old session cannot reuse the replacement audit'

# Explicit identity supplied by a host hook or caller always takes precedence.
VS_SESSION_ID=explicit-session CODEX_THREAD_ID=manual-two bash "$ROOT/scripts/check-versions.sh" >/dev/null 2>&1
assert_exit_code 0 "$?" 'explicit session audit succeeds'
assert_eq explicit-session "$(jq -r .session .version-sentinel/audit.json)" 'explicit VS_SESSION_ID wins over Codex environment'
output=$(hook explicit-session); status=$?
assert_exit_code 0 "$status" "explicit session hook accepts its audit ($output)"

# Hosts without an identity retain the prior startup/manual retry behavior.
bash "$ROOT/scripts/check-versions.sh" >/dev/null 2>&1
assert_exit_code 0 "$?" 'audit retry without host identity succeeds'
assert_eq explicit-session "$(jq -r .session .version-sentinel/audit.json)" 'identity-free retry retains the prior recorded session'

# Session detection must not turn a failed online audit into authorization.
VS_FIXTURE_NETWORK_FAIL=1 CODEX_THREAD_ID=failed-session bash "$ROOT/scripts/check-versions.sh" >/dev/null 2>&1
assert_exit_code 2 "$?" 'failed online audit still fails'
output=$(hook failed-session); status=$?
assert_exit_code 2 "$status" 'matching session cannot use failed audit evidence'
assert_eq pending "$(jq -r .status .version-sentinel/audit.json)" 'failed audit revokes the earlier success'

cmp -s "$VS_TMPDIR/launch/package.json" "$VS_TMPDIR/launch-original.json"
assert_exit_code 0 "$?" 'unrelated npm overrides remain unchanged'
[[ ! -e "$VS_TMPDIR/launch/.version-sentinel" ]] || _fail 'explicit workdir audit changed the launch project state'
finish_test
