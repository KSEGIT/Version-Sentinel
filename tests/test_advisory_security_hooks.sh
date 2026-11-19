#!/usr/bin/env bash
# Public hooks preserve findings without running providers or controlling tools.
set -u
VS_TEST_NAME=advisory-security-hooks
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/tests/assert.sh"
VS_TMPDIR=$(mktemp -d)
trap 'rm -rf "$VS_TMPDIR"' EXIT
cp -R "$ROOT/scripts" "$VS_TMPDIR/scripts"
mkdir "$VS_TMPDIR/project"
cd "$VS_TMPDIR/project" || exit 1
export SECURITY_CALLS="$VS_TMPDIR/security-calls"
cat > "$VS_TMPDIR/scripts/security-check.sh" <<'PROVIDER'
#!/usr/bin/env bash
printf '%s\n' "$1" >> "$SECURITY_CALLS"
if [[ "${VS_HOOK_LOCAL_ONLY:-0}" != 1 ]]; then
  echo 'BLOCKED: version-sentinel. Public hook did not request local evidence.' >&2
  exit 2
fi
if [[ "$1" == audit ]]; then
  echo 'BLOCKED: version-sentinel. Public hook tried an online provider.' >&2
  exit 2
fi
echo 'security finding: {"ids":["GHSA-fixture-low"],"severity":"low","links":["https://osv.dev/vulnerability/GHSA-fixture-low"],"title":"quoted \"advisory\""}'
echo 'security finding: {"ids":["CVE-2026-12345"],"severity":"moderate","links":["https://osv.dev/vulnerability/CVE-2026-12345"]}' >&2
echo '{"continue":false,"decision":"block","hookSpecificOutput":{"permissionDecision":"deny"}}'
if [[ "${SECURITY_FIXTURE_FAIL:-0}" == 1 ]]; then
  echo 'BLOCKED: version-sentinel. security unknown/incomplete' >&2
  exit 2
fi
PROVIDER
payload='{"tool_name":"Write","tool_input":{"file_path":"package-lock.json"}}'
for failed in 0 1; do
  for mode in '' --gemini --copilot; do
    : > "$SECURITY_CALLS"
    output=$(printf '%s' "$payload" | SECURITY_FIXTURE_FAIL="$failed" bash "$VS_TMPDIR/scripts/auto-record.sh" "$mode" 2>"$VS_TMPDIR/stderr"); status=$?
    assert_exit_code 0 "$status" "post hook continues ($failed $mode)"
    assert_eq '' "$(cat "$VS_TMPDIR/stderr")" "post diagnostics stay in warning JSON ($failed $mode)"
    printf '%s' "$output" | jq -e '
      .systemMessage | contains("WARNING") and contains("Work may continue") and
      contains("GHSA-fixture-low") and contains("https://osv.dev/vulnerability/GHSA-fixture-low") and
      contains("CVE-2026-12345")' >/dev/null 2>&1
    assert_exit_code 0 "$?" "post hook preserves escaped low and moderate findings ($failed $mode)"
    printf '%s' "$output" | jq -e '
      .systemMessage | split("\n")[] | select(startswith("security finding: ")) |
      sub("^security finding: "; "") | fromjson | select(.ids[0] == "GHSA-fixture-low") |
      .title == "quoted \"advisory\""' >/dev/null 2>&1
    assert_exit_code 0 "$?" "post advisory quotes round-trip ($failed $mode)"
    printf '%s' "$output" | jq -e '
      [.. | objects | keys[] | select(. == "continue" or . == "decision" or . == "permissionDecision" or . == "stopReason")] | length == 0' >/dev/null 2>&1
    assert_exit_code 0 "$?" "post hook has no lifecycle control fields ($failed $mode)"
    if [[ "$mode" == --gemini ]]; then
      printf '%s' "$output" | jq -e 'has("hookSpecificOutput") | not' >/dev/null 2>&1
    else
      printf '%s' "$output" | jq -e '.hookSpecificOutput.hookEventName == "PostToolUse" and .hookSpecificOutput.additionalContext == .systemMessage' >/dev/null 2>&1
    fi
    assert_exit_code 0 "$?" "post hook uses its platform event ($failed $mode)"
    assert_eq gate "$(cat "$SECURITY_CALLS")" "post hook never starts an online scan ($failed $mode)"
  done
done
# Pre-tool validators must inherit the same local-only boundary.
for script in detect-install-cmd detect-manifest-edit; do
  cat > "$VS_TMPDIR/scripts/validate-$script.sh" <<'VALIDATOR'
#!/usr/bin/env bash
if [[ "${VS_HOOK_LOCAL_ONLY:-0}" == 1 ]]; then
  echo 'security finding: {"ids":["GHSA-local-only"],"severity":"low"}' >&2
fi
VALIDATOR
  output=$(printf '{}' | bash "$VS_TMPDIR/scripts/$script.sh"); status=$?
  assert_exit_code 0 "$status" "$script continues with nonblocking findings"
  printf '%s' "$output" | jq -e '.systemMessage | contains("GHSA-local-only")' >/dev/null 2>&1
  assert_exit_code 0 "$?" "$script requests local evidence and retains successful diagnostics"
done
# A large advisory must not turn into the generic missing-runtime fallback.
cat > "$VS_TMPDIR/scripts/validate-detect-install-cmd.sh" <<'VALIDATOR'
#!/usr/bin/env bash
python3 - <<'PY'
print('security finding: ' + 'x' * 1200000 + ' GHSA-large https://osv.dev/vulnerability/GHSA-large')
PY
VALIDATOR
output=$(printf '{}' | bash "$VS_TMPDIR/scripts/detect-install-cmd.sh" 2>"$VS_TMPDIR/large.err"); status=$?
assert_exit_code 0 "$status" 'large advisory continues'
printf '%s' "$output" | jq -e '.systemMessage | contains("GHSA-large https://osv.dev/vulnerability/GHSA-large")' >/dev/null 2>&1
assert_exit_code 0 "$?" 'large advisory retains its identifier and source link'
finish_test
