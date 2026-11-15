#!/usr/bin/env bash
# Integration contract independent of provider implementation and live networks.
VS_TEST_NAME=security-hooks
TEST_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$TEST_DIR/assert.sh"
ROOT="$(cd "$TEST_DIR/.." && pwd)"
VS_TMPDIR=$(mktemp -d)
trap 'rm -rf "$VS_TMPDIR"' EXIT
cp -R "$ROOT/scripts" "$VS_TMPDIR/scripts"
mkdir -p "$VS_TMPDIR/project"
export SECURITY_CALLS="$VS_TMPDIR/calls" SECURITY_FAIL_ACTION=''
cat > "$VS_TMPDIR/scripts/security-check.sh" <<'MOCK'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$SECURITY_CALLS"
if [[ "$1" == "${SECURITY_FAIL_ACTION:-}" ]]; then
  echo 'GHSA-fixture HIGH https://osv.dev/vulnerability/GHSA-fixture affected <2.0.0 fixed 2.0.0 provider osv'
  echo 'BLOCKED: version-sentinel. security unknown/incomplete' >&2
  exit 2
fi
MOCK
source "$TEST_DIR/registry-fixture.sh"
registry_fixture_setup
cd "$VS_TMPDIR/project" || exit 1
VS_TEST_CANONICAL_ROOT=$(pwd -P)
printf '%s\n' '{"dependencies":{"lodash":"4.17.21"}}' > package.json
result=$(bash "$VS_TMPDIR/scripts/check-versions.sh" 2>&1); status=$?
assert_exit_code 0 "$status" 'complete audit includes security'
assert_contains "$(cat "$SECURITY_CALLS" 2>/dev/null)" "audit $PWD" 'online audit calls security provider engine'
result=$(SECURITY_FAIL_ACTION=audit bash "$VS_TMPDIR/scripts/check-versions.sh" 2>&1); status=$?
assert_exit_code 2 "$status" 'security failure prevents completed audit'
bash "$VS_TMPDIR/scripts/audit-state.sh" gate "$PWD" >/dev/null 2>&1
assert_exit_code 2 "$?" 'security failure revokes previous startup evidence'
bash "$VS_TMPDIR/scripts/check-versions.sh" >/dev/null 2>&1
result=$(SECURITY_FAIL_ACTION=gate bash "$VS_TMPDIR/scripts/audit-state.sh" gate "$PWD" 2>&1); status=$?
assert_exit_code 2 "$status" 'current version evidence cannot waive security gate'
# Proposal scan runs before the intentional-pin/version evidence decision.
bash "$VS_TMPDIR/scripts/vs-record.sh" npm lodash 4.17.21 'intentional: compatibility pin' >/dev/null 2>&1
result=$(SECURITY_FAIL_ACTION=proposed bash "$VS_TMPDIR/scripts/check-sidecar.sh" npm lodash 4.17.21 2>&1); status=$?
assert_exit_code 2 "$status" 'intentional pins cannot waive advisory findings'
assert_contains "$(cat "$SECURITY_CALLS" 2>/dev/null)" "proposed $VS_TEST_CANONICAL_ROOT lodash 4.17.21" 'exact candidate reaches security engine'

# Manifest proposal failures must retain provider findings written to stdout.
result=$(printf '%s\n' '{"tool_name":"Write","tool_input":{"file_path":"package.json","content":"{\"dependencies\":{\"lodash\":\"4.17.20\"}}"}}' | SECURITY_FAIL_ACTION=proposed bash "$VS_TMPDIR/scripts/detect-manifest-edit.sh" 2>&1); status=$?
assert_exit_code 2 "$status" 'manifest proposal blocks advisory finding'
assert_contains "$result" 'GHSA-fixture HIGH https://osv.dev/vulnerability/GHSA-fixture' 'manifest proposal preserves advisory diagnostics'

# Lockfiles are relevant before direct writes, including patch post-images.
: > "$SECURITY_CALLS"
result=$(printf '%s\n' '{"tool_name":"Write","tool_input":{"file_path":"package-lock.json","content":"{\"lockfileVersion\":3,\"packages\":{}}"}}' | SECURITY_FAIL_ACTION=proposed-lock bash "$VS_TMPDIR/scripts/detect-manifest-edit.sh" 2>&1); status=$?
assert_exit_code 2 "$status" 'direct lock write blocks failed proposal scan'
assert_contains "$result" 'GHSA-fixture HIGH https://osv.dev/vulnerability/GHSA-fixture' 'lock proposal preserves advisory diagnostics'
assert_contains "$(cat "$SECURITY_CALLS")" "proposed-lock $VS_TEST_CANONICAL_ROOT" 'lock post-image reaches security engine'

# Post hooks must skip unrelated tools, scan changed npm state, and never record.
: > "$SECURITY_CALLS"
printf '%s\n' '{"tool_name":"Read","tool_input":{"file_path":"package.json"}}' | bash "$VS_TMPDIR/scripts/auto-record.sh"
assert_eq '' "$(cat "$SECURITY_CALLS")" 'read tool does not scan'
printf '%s\n' '{"tool_name":"Edit","tool_input":{"file_path":"README.md"}}' | bash "$VS_TMPDIR/scripts/auto-record.sh"
assert_eq '' "$(cat "$SECURITY_CALLS")" 'unrelated edit does not scan'
cp .version-sentinel/checks.json "$VS_TMPDIR/checks-before"
printf '%s\n' '{"tool_name":"Edit","tool_input":{"file_path":"package-lock.json"}}' | SECURITY_FAIL_ACTION=gate bash "$VS_TMPDIR/scripts/auto-record.sh"
assert_contains "$(cat "$SECURITY_CALLS")" "audit $VS_TEST_CANONICAL_ROOT" 'changed lock triggers scan'
cmp -s .version-sentinel/checks.json "$VS_TMPDIR/checks-before"
assert_exit_code 0 "$?" 'post scan never creates version verification'
: > "$SECURITY_CALLS"
printf '%s\n' '{"tool_name":"Bash","tool_input":{"command":"npm install lodash@4.17.21"}}' | bash "$VS_TMPDIR/scripts/auto-record.sh"
assert_contains "$(cat "$SECURITY_CALLS")" "gate $VS_TEST_CANONICAL_ROOT" 'successful package command checks current security state'
if [[ "$(cat "$SECURITY_CALLS")" == *"audit "* ]]; then _fail 'current security evidence avoids repeat network'; fi
printf '%s\n' '{"tool_name":"Write","tool_input":{"file_path":"package.json"}}' | SECURITY_FAIL_ACTION=audit bash "$VS_TMPDIR/scripts/auto-record.sh"
assert_exit_code 0 "$?" 'current security evidence skips redundant audit'
# Changed-state audit failures remain visible and block further dependency work.
: > "$SECURITY_CALLS"
result=$(printf '%s\n' '{"tool_name":"apply_patch","tool_input":{"patch":"*** Begin Patch\n*** Update File: package-lock.json\n@@\n*** End Patch"}}' | SECURITY_FAIL_ACTION=gate bash "$VS_TMPDIR/scripts/auto-record.sh" 2>&1); status=$?
assert_exit_code 0 "$status" 'patch triggers a replacement security scan'
assert_contains "$(cat "$SECURITY_CALLS")" "audit $VS_TEST_CANONICAL_ROOT" 'patch lock header is relevant'
mkdir -p child
: > "$SECURITY_CALLS"
printf '%s\n' '{"tool_name":"exec_command","tool_input":{"command":"npm install lodash@4.17.21","workdir":"child"}}' | SECURITY_FAIL_ACTION=gate bash "$VS_TMPDIR/scripts/auto-record.sh"
assert_contains "$(cat "$SECURITY_CALLS")" "audit $VS_TEST_CANONICAL_ROOT/child" 'post command uses actual workdir'
# Raw shell writes and heredocs also inspect the actual project snapshot.
: > "$SECURITY_CALLS"
printf '%s\n' '{"tool_name":"Bash","tool_input":{"command":"printf data > package-lock.json"}}' | SECURITY_FAIL_ACTION=gate bash "$VS_TMPDIR/scripts/auto-record.sh"
assert_contains "$(cat "$SECURITY_CALLS")" "audit $VS_TEST_CANONICAL_ROOT" 'raw shell mutation uses actual project snapshot'
: > "$SECURITY_CALLS"
printf '%s\n' '{"tool_name":"Bash","tool_input":{"command":"cat > out <<EOF\nnpm install lodash@4.17.21\nEOF"}}' | bash "$VS_TMPDIR/scripts/auto-record.sh"
assert_exit_code 0 "$?" 'unsupported command parsing still checks unchanged snapshot without false install failure'
assert_contains "$(cat "$SECURITY_CALLS")" "gate $VS_TEST_CANONICAL_ROOT" 'heredoc fallback checks actual project'
# Make both gate and audit fail to show provider errors are not swallowed.
sed 's/if \[\[ "$1" == "${SECURITY_FAIL_ACTION:-}" \]\]; then/if [[ "$1" == gate || "$1" == audit ]]; then/' "$VS_TMPDIR/scripts/security-check.sh" > "$VS_TMPDIR/failing-security"
cp "$VS_TMPDIR/failing-security" "$VS_TMPDIR/scripts/security-check.sh"
result=$(printf '%s\n' '{"tool_name":"Write","tool_input":{"file_path":"package.json"}}' | bash "$VS_TMPDIR/scripts/auto-record.sh" 2>&1); status=$?
assert_exit_code 2 "$status" 'failed post scan reports blocking status'
assert_contains "$result" 'security unknown/incomplete' 'provider diagnostic remains visible'
# Claude post-shell dispatch must run for raw writes without manager keywords.
post_shell_handlers=$(jq '[.hooks.PostToolUse[] | select(.matcher == "Bash") | .hooks[]] | length' "$ROOT/hooks/hooks.json" | tr -d '\r')
assert_eq 1 "$post_shell_handlers" 'one post-shell snapshot handler'
post_shell_filtered=$(jq '[.hooks.PostToolUse[] | select(.matcher == "Bash") | .hooks[] | select(has("if"))] | length' "$ROOT/hooks/hooks.json" | tr -d '\r')
assert_eq 0 "$post_shell_filtered" 'raw python/printf shell writes reach post snapshot checks'
finish_test
