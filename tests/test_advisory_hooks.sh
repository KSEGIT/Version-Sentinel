#!/usr/bin/env bash
# Hook failures must never deny a tool or instruct an agent to stop.
set -u
VS_TEST_NAME=advisory-hooks
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/tests/assert.sh"
VS_TMPDIR=$(mktemp -d)
trap 'rm -rf "$VS_TMPDIR"' EXIT
cd "$VS_TMPDIR" || exit 1
assert_advisory() {
  local output="$1" status="$2" label="$3"
  assert_exit_code 0 "$status" "$label continues"
  assert_contains "$output" 'WARNING' "$label warns"
  assert_contains "$output" 'Work may continue' "$label permits work"
  if printf '%s' "$output" | grep -Eqi 'BLOCKED|REQUIRED before|deny|ask.*consent|remains blocked'; then
    _fail "$label contains blocking instructions: $output"
  fi
}
assert_action_names() {
  local output="$1" action="$2" label="$3"
  assert_contains "$output" "/version-sentinel:$action" "$label names the Claude/Kimi command"
  assert_contains "$output" "\$version-sentinel:$action" "$label names the Codex skill"
  assert_contains "$output" "Copilot CLI/Zed: $action skill" "$label names the other skill entry"
}
for script in detect-manifest-edit detect-install-cmd auto-record session-start; do
  output=$(printf 'invalid json' | bash "$ROOT/scripts/$script.sh" 2>&1); status=$?
  assert_advisory "$output" "$status" "$script malformed input"
done
output=$(printf '%s' '{"tool_name":"Bash","tool_input":{"command":"npm install lodash"}}' |
  bash "$ROOT/scripts/detect-install-cmd.sh" 2>&1); status=$?
assert_advisory "$output" "$status" 'unchecked install'
assert_contains "$output" '/vs-refresh' 'tool warning recommends the project refresh command'
assert_action_names "$output" vs-refresh 'project warning'
[[ "$output" != *'/vs-record'* ]] || _fail 'missing project evidence calls for a project refresh'
printf '%s' "$output" | jq -e '.systemMessage | contains("WARNING")' >/dev/null 2>&1
assert_exit_code 0 "$?" 'tool warning is visible in stdout JSON'
output=$(printf '%s' '{"tool_name":"Write","tool_input":{"file_path":"package.json","content":"{\"dependencies\":{\"lodash\":\"99.0.0\"}}"}}' |
  bash "$ROOT/scripts/detect-manifest-edit.sh" 2>&1); status=$?
assert_advisory "$output" "$status" 'unchecked manifest edit'
cp -R "$ROOT/scripts" "$VS_TMPDIR/broken-scripts"
rm "$VS_TMPDIR/broken-scripts/lib/path_helpers.py"
output=$(printf '%s' '{"tool_name":"Write","tool_input":{"file_path":"package.json","content":"{}"}}' |
  bash "$VS_TMPDIR/broken-scripts/detect-manifest-edit.sh" 2>&1); status=$?
assert_advisory "$output" "$status" 'broken internal prerequisite'
printf '%s\n' '#!/usr/bin/env bash' 'printf '\''%s\n'\'' '\''{"continue":false}'\''' > "$VS_TMPDIR/broken-scripts/validate-detect-install-cmd.sh"
output=$(printf '{}' | bash "$VS_TMPDIR/broken-scripts/detect-install-cmd.sh"); status=$?
assert_advisory "$output" "$status" 'unexpected validator control output'
printf '%s' "$output" | jq -e 'has("continue") | not' >/dev/null
assert_exit_code 0 "$?" 'validator cannot forward lifecycle control fields'
printf '%s\n' '#!/usr/bin/env bash' 'echo "BLOCKED: version-sentinel. BLOCKED: version-sentinel. Nested validation failed." >&2' 'exit 2' > "$VS_TMPDIR/broken-scripts/validate-detect-install-cmd.sh"
output=$(printf '{}' | bash "$VS_TMPDIR/broken-scripts/detect-install-cmd.sh"); status=$?
assert_advisory "$output" "$status" 'nested strict failure'
assert_action_names "$output" vs-refresh 'fallback warning'
assert_action_names "$output" vs-record 'fallback warning'
for mode in '' --gemini --copilot; do
  output=$(printf 'invalid json' | bash "$ROOT/scripts/session-start.sh" "$mode" 2>"$VS_TMPDIR/startup.err"); status=$?
  assert_advisory "$output" "$status" "startup $mode"
  assert_contains "$output" '/vs-refresh' "startup $mode recommends the project refresh command"
  assert_action_names "$output" vs-refresh "startup $mode"
  printf '%s' "$output" | jq -e '.systemMessage and .hookSpecificOutput.additionalContext' >/dev/null
  assert_exit_code 0 "$?" "startup $mode emits valid warning JSON"
done
# A failed startup audit must also leave unrelated .NET work available.
printf '%s\n' '{}' > package.json
printf '%s\n' '-r other.txt' > requirements.txt
for command in 'dotnet build' 'dotnet test' 'dotnet restore'; do
  output=$(jq -nc --arg command "$command" '{tool_name:"Bash",tool_input:{command:$command}}' |
    bash "$ROOT/scripts/detect-install-cmd.sh" 2>&1); status=$?
  assert_advisory "$output" "$status" "$command after failed audit"
done
output=$(printf '{}' | bash "$ROOT/scripts/session-start.sh" 2>&1); status=$?
assert_advisory "$output" "$status" 'invalid requirements startup audit'
assert_contains "$output" 'optional' 'startup explains optional manual audit'
mkdir "$VS_TMPDIR/no-tools"
for script in detect-install-cmd auto-record; do
  output=$(PATH="$VS_TMPDIR/no-tools" /bin/bash "$ROOT/scripts/$script.sh" <<< '{}' 2>"$VS_TMPDIR/missing-tools.err"); status=$?
  assert_advisory "$output" "$status" "$script missing prerequisites"
  printf '%s' "$output" | jq -e '.systemMessage | contains("WARNING")' >/dev/null
  assert_exit_code 0 "$?" "$script missing prerequisites still emits visible JSON"
done
rm "$VS_TMPDIR/broken-scripts/lib/advisory-hook.sh"
output=$(printf '{}' | bash "$VS_TMPDIR/broken-scripts/detect-install-cmd.sh" 2>"$VS_TMPDIR/missing-helper.err"); status=$?
assert_advisory "$output" "$status" 'missing advisory runtime'
printf '%s' "$output" | jq -e '.systemMessage | contains("WARNING")' >/dev/null
assert_exit_code 0 "$?" 'missing advisory runtime still emits visible JSON'
finish_test
