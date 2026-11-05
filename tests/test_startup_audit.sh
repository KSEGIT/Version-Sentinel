#!/usr/bin/env bash
# Missing evidence, changed files, failed lookups, and recovery must keep the gate closed.
VS_TEST_NAME="startup-audit"
TESTS_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$TESTS_DIR/.." && pwd)"
source "$TESTS_DIR/assert.sh"
VS_AUDIT_TMP=$(mktemp -d)
trap 'rm -rf "$VS_AUDIT_TMP"' EXIT
mkdir -p "$VS_AUDIT_TMP/bin" "$VS_AUDIT_TMP/project"
cat > "$VS_AUDIT_TMP/bin/curl" <<'CURL'
#!/usr/bin/env bash
[[ "${AUDIT_FIXTURE_FAIL:-0}" == 1 ]] && exit 7
case "${@: -1}" in
  https://registry.npmjs.org/lodash)
    printf '%s\n' '{"name":"lodash","dist-tags":{"latest":"4.17.21"},"versions":{"4.17.20":{},"4.17.21":{}}}' ;;
  *) exit 22 ;;
esac
CURL
chmod +x "$VS_AUDIT_TMP/bin/curl"
export PATH="$VS_AUDIT_TMP/bin:$PATH" VS_ETAG_DISABLE=1 VS_REGISTRY_RETRIES=1 VS_REGISTRY_RETRY_DELAY=0
cd "$VS_AUDIT_TMP/project"
result=$(bash "$ROOT/scripts/check-versions.sh" 2>&1); status=$?
assert_exit_code 2 "$status" "zero manifests cannot produce completed audit"
assert_contains "$result" "Ask" "missing-manifest asks for user consent"
result=$(printf '{}' | bash "$ROOT/scripts/session-start.sh" 2>"$VS_AUDIT_TMP/startup.err"); status=$?
assert_exit_code 0 "$status" "missing-manifest startup is advisory"
context=$(printf '%s' "$result" | jq -r '.hookSpecificOutput.additionalContext' 2>/dev/null)
assert_contains "$context" "Required dependency manifest is missing" "startup preserves missing-manifest diagnostic"
assert_contains "$context" "Ask Daniel" "startup preserves recovery consent guidance"

printf '%s\n' '{"dependencies":{"lodash":"4.17.20"}}' > package.json
result=$(bash "$ROOT/scripts/audit-state.sh" gate "$PWD" 2>&1); status=$?
assert_exit_code 2 "$status" "dependency work blocks before audit"
result=$(bash "$ROOT/scripts/check-versions.sh" 2>&1); status=$?
assert_exit_code 0 "$status" "newer releases do not fail audit"
assert_contains "$result" "DRIFT" "newer release reported"
bash "$ROOT/scripts/audit-state.sh" gate "$PWD" >/dev/null 2>&1
assert_exit_code 0 "$?" "successful online audit opens gate"

printf '%s\n' '{"dependencies":{"lodash":"4.17.21"}}' > package.json
bash "$ROOT/scripts/audit-state.sh" gate "$PWD" >/dev/null 2>&1
assert_exit_code 2 "$?" "manifest change invalidates evidence"
bash "$ROOT/scripts/check-versions.sh" >/dev/null 2>&1
printf '%s\n' '{"lockfileVersion":3}' > package-lock.json
bash "$ROOT/scripts/audit-state.sh" gate "$PWD" >/dev/null 2>&1
assert_exit_code 2 "$?" "new lockfile invalidates evidence"
bash "$ROOT/scripts/check-versions.sh" >/dev/null 2>&1
AUDIT_FIXTURE_FAIL=1 bash "$ROOT/scripts/check-versions.sh" >/dev/null 2>&1
assert_exit_code 2 "$?" "lookup failure is audit failure"
bash "$ROOT/scripts/audit-state.sh" gate "$PWD" >/dev/null 2>&1
assert_exit_code 2 "$?" "failed audit invalidates previous success"
bash "$ROOT/scripts/check-versions.sh" >/dev/null 2>&1
rm package.json
result=$(bash "$ROOT/scripts/check-versions.sh" 2>&1); status=$?
assert_exit_code 2 "$status" "deleted required manifest blocks audit"
assert_contains "$result" "package.json" "deleted manifest named"
assert_contains "$result" "Ask" "deleted manifest requires consent"
bash "$ROOT/scripts/audit-state.sh" recovery-allowed "$PWD" package.json >/dev/null 2>&1
assert_exit_code 2 "$?" "recovery unavailable before explicit consent"
bash "$ROOT/scripts/recover-manifest.sh" approve package.json >/dev/null 2>&1
assert_exit_code 2 "$?" "approval requires explicit user-confirmed flag and reason"
bash "$ROOT/scripts/recover-manifest.sh" approve package.json --user-confirmed 'Daniel approved restoring this manifest' >/dev/null 2>&1
assert_exit_code 0 "$?" "explicit consent records recovery approval"
[[ ! -e package.json ]] || _fail "approval must not create guessed manifest"
bash "$ROOT/scripts/audit-state.sh" recovery-allowed "$PWD" package.json >/dev/null 2>&1
assert_exit_code 0 "$?" "approved exact missing path can be recovered"
bash "$ROOT/scripts/audit-state.sh" recovery-allowed "$PWD" elsewhere/package.json >/dev/null 2>&1
assert_exit_code 2 "$?" "consent does not cover another path"
printf '%s\n' '{"dependencies":{"lodash":"4.17.21"}}' > package.json
bash "$ROOT/scripts/audit-state.sh" recovery-allowed "$PWD" package.json >/dev/null 2>&1
assert_exit_code 2 "$?" "consent cannot authorize replacing a valid manifest"
bash "$ROOT/scripts/audit-state.sh" gate "$PWD" >/dev/null 2>&1
assert_exit_code 2 "$?" "recovery still requires a completed new audit"
bash "$ROOT/scripts/check-versions.sh" >/dev/null 2>&1
assert_exit_code 0 "$?" "audit succeeds after recovery"


# Startup uses hook cwd even when invoked by a relative plugin path.
printf '%s\n' '{"dependencies":{"lodash":"4.17.21"}}' > package.json
result=$(cd "$ROOT" && jq -nc --arg cwd "$VS_AUDIT_TMP/project" '{cwd:$cwd,session_id:"session-one"}' | bash scripts/session-start.sh 2>&1); status=$?
assert_exit_code 0 "$status" "startup resolves plugin script path before changing project cwd"
assert_contains "$result" 'version-sentinel: mandatory online dependency audit completed; no dependency versions changed.' "successful default startup keeps text output"
VS_SESSION_ID=session-one bash "$ROOT/scripts/audit-state.sh" gate "$PWD" >/dev/null 2>&1
assert_exit_code 0 "$?" "startup evidence matches current session"
VS_SESSION_ID=session-two bash "$ROOT/scripts/audit-state.sh" gate "$PWD" >/dev/null 2>&1
assert_exit_code 2 "$?" "another session cannot reuse startup evidence"
# A manual retry preserves the current session identity recorded by startup.
bash "$ROOT/scripts/check-versions.sh" >/dev/null 2>&1
VS_SESSION_ID=session-one bash "$ROOT/scripts/audit-state.sh" gate "$PWD" >/dev/null 2>&1
assert_exit_code 0 "$?" "manual audit retry retains startup session identity"

# An expected audit block becomes visible startup context without opening gates.
AUDIT_FIXTURE_FAIL=1 bash "$ROOT/scripts/session-start.sh" <<< '{}' >"$VS_AUDIT_TMP/blocked.json" 2>"$VS_AUDIT_TMP/startup.err"; status=$?
assert_exit_code 0 "$status" "registry-failed startup is advisory"
result=$(cat "$VS_AUDIT_TMP/blocked.json")
printf '%s' "$result" | jq -e '.systemMessage | contains("dependency work remains blocked")' >/dev/null 2>&1
assert_exit_code 0 "$?" "blocked startup displays a user-visible warning"
context=$(printf '%s' "$result" | jq -r '.hookSpecificOutput | select(.hookEventName == "SessionStart") | .additionalContext' 2>/dev/null)
assert_contains "$context" "lookup-failed" "startup preserves failed registry table"
assert_contains "$context" 'BLOCKED: version-sentinel. Mandatory audit failed due to registry lookup/manifest errors. Resolve the errors and rerun; version drift alone does not fail an audit.' "startup preserves exact failed audit diagnostic"
assert_contains "$context" "dependency work remains blocked" "startup does not claim successful audit"
assert_contains "$context" "$ROOT/scripts/check-versions.sh" "startup gives runnable audit path"
bash "$ROOT/scripts/audit-state.sh" gate "$PWD" >/dev/null 2>&1
assert_exit_code 2 "$?" "advisory startup revokes previous successful evidence"
result=$(jq -nc --arg cwd "$PWD" '{cwd:$cwd,tool_name:"Bash",tool_input:{command:"npm install"}}' |
  bash "$ROOT/scripts/detect-install-cmd.sh" 2>&1); status=$?
assert_exit_code 2 "$status" "bare install stays blocked after advisory startup"
assert_contains "$result" 'Startup dependency audit is missing, failed, expired, or project files changed' "bare install requires successful audit"
result=$(jq -nc --arg cwd "$PWD" '{cwd:$cwd,tool_name:"Write",tool_input:{file_path:"package.json",content:"{\"dependencies\":{\"lodash\":\"4.17.20\"}}"}}' |
  bash "$ROOT/scripts/detect-manifest-edit.sh" 2>&1); status=$?
assert_exit_code 2 "$status" "dependency edit stays blocked after advisory startup"
assert_contains "$result" 'Startup dependency audit is missing, failed, expired, or project files changed' "dependency edit requires successful audit"

# Deliberately unsupported fixture includes still fail the direct audit.
printf '%s\n' '-r other.txt' > requirements.txt
result=$(bash "$ROOT/scripts/check-versions.sh" 2>&1); status=$?
assert_exit_code 2 "$status" "unsupported requirements include still fails direct audit"
assert_contains "$result" "unsupported requirements include name: other.txt" "direct audit explains unsupported include"
result=$(bash "$ROOT/scripts/session-start.sh" <<< '{}' 2>"$VS_AUDIT_TMP/startup.err"); status=$?
assert_exit_code 0 "$status" "unsupported include startup is advisory"
context=$(printf '%s' "$result" | jq -r '.hookSpecificOutput.additionalContext' 2>/dev/null)
assert_contains "$context" 'BLOCKED: version-sentinel. unsupported requirements include name: other.txt; use requirements*.txt or constraints*.txt' "startup preserves exact unsupported include diagnostic"
rm requirements.txt

# Unexpected audit failures retain their exit status and diagnostic.
cp -R "$ROOT/scripts" "$VS_AUDIT_TMP/crash-scripts"
for crash_status in 2 17; do
  printf 'echo "unexpected audit crash" >&2\nexit %s\n' "$crash_status" > "$VS_AUDIT_TMP/crash-scripts/check-versions.sh"
  for mode in '' --gemini; do
    result=$(bash "$VS_AUDIT_TMP/crash-scripts/session-start.sh" "$mode" <<< '{}' 2>&1); status=$?
    assert_exit_code "$crash_status" "$status" "unexpected audit crash $crash_status remains a failure ($mode)"
    assert_contains "$result" "unexpected audit crash" "unexpected audit failure remains visible ($mode)"
  done
done
printf '%s\n' 'invalid json' | bash "$ROOT/scripts/session-start.sh" >/dev/null 2>&1
assert_exit_code 2 "$?" "invalid startup payload blocks audit"
bash "$ROOT/scripts/audit-state.sh" gate "$PWD" >/dev/null 2>&1
assert_exit_code 2 "$?" "startup payload failure revokes older audit evidence"

# Explicit install inputs must belong to the audited inventory.
bash "$ROOT/scripts/check-versions.sh" >/dev/null 2>&1
bash "$ROOT/scripts/audit-state.sh" covers "$PWD" package.json >/dev/null 2>&1
assert_exit_code 0 "$?" "audited explicit manifest covered"
printf '%s\n' 'lodash==4.17.21' > extra.txt
bash "$ROOT/scripts/audit-state.sh" covers "$PWD" extra.txt >/dev/null 2>&1
assert_exit_code 2 "$?" "unscanned explicit requirements file not covered"
# Includes are validated and become part of the snapshot.
printf '%s\n' '-r requirements-base.txt' > requirements.txt
result=$(bash "$ROOT/scripts/check-versions.sh" 2>&1); status=$?
assert_exit_code 2 "$status" "missing requirements include blocks audit"
assert_contains "$result" "requirements-base.txt" "missing include path named"
printf '' > requirements-base.txt
bash "$ROOT/scripts/check-versions.sh" >/dev/null 2>&1
assert_exit_code 0 "$?" "existing requirements include can be audited"
bash "$ROOT/scripts/audit-state.sh" covers "$PWD" requirements-base.txt >/dev/null 2>&1
assert_exit_code 0 "$?" "requirements include belongs to audit"
printf '%s\n' '-r \' 'requirements-base.txt' > requirements.txt
bash "$ROOT/scripts/check-versions.sh" >/dev/null 2>&1
assert_exit_code 0 "$?" "continued requirements include can be audited"
bash "$ROOT/scripts/audit-state.sh" covers "$PWD" requirements-base.txt >/dev/null 2>&1
assert_exit_code 0 "$?" "continued requirements include is part of audited inventory"
# Expired evidence cannot satisfy the gate.
python3 - <<'EXPIRE'
import json
p='.version-sentinel/audit.json'
data=json.load(open(p)); data['checkedAt']=0
json.dump(data,open(p,'w'))
EXPIRE
bash "$ROOT/scripts/audit-state.sh" gate "$PWD" >/dev/null 2>&1
assert_exit_code 2 "$?" "audit evidence expires"

# Copying project state to another project must not open its gate.
mkdir "$VS_AUDIT_TMP/copied"
cp package.json package-lock.json "$VS_AUDIT_TMP/copied/"
cp -R .version-sentinel "$VS_AUDIT_TMP/copied/"
bash "$ROOT/scripts/audit-state.sh" gate "$VS_AUDIT_TMP/copied" >/dev/null 2>&1
assert_exit_code 2 "$?" "audit evidence is project-bound"

printf '%s\n' '{not json' > package.json
result=$(bash "$ROOT/scripts/check-versions.sh" 2>&1); status=$?
assert_exit_code 2 "$status" "invalid manifest cannot be audited"
assert_contains "$result" "Ask" "invalid manifest repair requires consent"
bash "$ROOT/scripts/recover-manifest.sh" approve package.json --user-confirmed 'Daniel approved repair' >/dev/null 2>&1
assert_exit_code 0 "$?" "invalid manifest approval accepted"
printf '%s\n' '{different invalid json' > package.json
bash "$ROOT/scripts/audit-state.sh" recovery-allowed "$PWD" package.json >/dev/null 2>&1
assert_exit_code 2 "$?" "approval is bound to original invalid content"

# A tracked deleted manifest is required even before the first local audit.
mkdir "$VS_AUDIT_TMP/tracked"
cd "$VS_AUDIT_TMP/tracked"
git init -q
git config user.email fixture@example.invalid
git config user.name Fixture
printf '{}' > package.json
git add package.json
git commit -qm fixture
rm package.json
result=$(bash "$ROOT/scripts/check-versions.sh" 2>&1); status=$?
assert_exit_code 2 "$status" "tracked missing manifest blocks first audit"
assert_contains "$result" "package.json" "tracked missing path named"

finish_test
