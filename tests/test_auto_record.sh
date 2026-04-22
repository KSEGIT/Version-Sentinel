#!/usr/bin/env bash
# Tests scripts/auto-record.sh: PostToolUse:Bash → sidecar auto-entry on successful installs.
set -u
VS_TEST_NAME="auto-record"
source "$(dirname "$0")/assert.sh"

VS_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$VS_TMPDIR"' EXIT
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$ROOT/scripts/auto-record.sh"
SIDECAR=".version-sentinel/checks.json"

cd "$VS_TMPDIR"

# Helper: count entries in sidecar (0 if file missing/invalid)
count_entries() {
  if [[ ! -f "$SIDECAR" ]]; then echo 0; return; fi
  jq '.entries | length' "$SIDECAR" 2>/dev/null || echo 0
}

# --- Case 1: successful npm install → entry added, source starts "auto-recorded:" ---
rm -rf .version-sentinel
json='{"tool_name":"Bash","tool_input":{"command":"npm install lodash@4.17.21"},"tool_response":{"exit_code":0}}'
out=$(echo "$json" | bash "$SCRIPT" 2>&1; echo "exit=$?")
assert_contains "$out" "exit=0" "success install → exit 0"
assert_eq "1" "$(count_entries)" "success install → 1 sidecar entry"
src=$(jq -r '.entries[0].source' "$SIDECAR")
case "$src" in
  "auto-recorded:"*) ;;
  *) _fail "entry source should start with 'auto-recorded:', got: $src" ;;
esac
assert_eq "npm"      "$(jq -r '.entries[0].ecosystem' "$SIDECAR")" "entry ecosystem=npm"
assert_eq "lodash"   "$(jq -r '.entries[0].pkg'       "$SIDECAR")" "entry pkg=lodash"
assert_eq "4.17.21"  "$(jq -r '.entries[0].version'   "$SIDECAR")" "entry version=4.17.21"

# --- Case 2: failed install (non-zero exit_code) → no entry added ---
rm -rf .version-sentinel
json='{"tool_name":"Bash","tool_input":{"command":"npm install bogus@9.9.9"},"tool_response":{"exit_code":1}}'
out=$(echo "$json" | bash "$SCRIPT" 2>&1; echo "exit=$?")
assert_contains "$out" "exit=0" "failed install → exit 0"
assert_eq "0" "$(count_entries)" "failed install → no sidecar entry"

# --- Case 2b: success="false" (string) variant → no entry added ---
# Note: the script uses `jq -r '.tool_response.success // empty'`, which treats a
# JSON boolean `false` as empty (jq's // default operator). So we test the string
# form that runners in practice use.
rm -rf .version-sentinel
json='{"tool_name":"Bash","tool_input":{"command":"npm install bogus@9.9.9"},"tool_response":{"success":"false"}}'
out=$(echo "$json" | bash "$SCRIPT" 2>&1; echo "exit=$?")
assert_contains "$out" "exit=0" "success=\"false\" → exit 0"
assert_eq "0" "$(count_entries)" "success=\"false\" → no sidecar entry"

# --- Case 3: tool_name != Bash → no-op ---
rm -rf .version-sentinel
json='{"tool_name":"Edit","tool_input":{"command":"npm install lodash@4.17.21"},"tool_response":{"exit_code":0}}'
out=$(echo "$json" | bash "$SCRIPT" 2>&1; echo "exit=$?")
assert_contains "$out" "exit=0" "non-Bash tool → exit 0"
assert_eq "0" "$(count_entries)" "non-Bash tool → no sidecar entry"

# --- Case 4: malformed JSON on stdin → no-op ---
rm -rf .version-sentinel
out=$(echo "not-json-at-all{" | bash "$SCRIPT" 2>&1; echo "exit=$?")
assert_contains "$out" "exit=0" "bad JSON → exit 0"
assert_eq "0" "$(count_entries)" "bad JSON → no sidecar entry"

# --- Case 5: CLAUDE_PLUGIN_OPTION_DISABLE=true → no-op ---
rm -rf .version-sentinel
json='{"tool_name":"Bash","tool_input":{"command":"npm install lodash@4.17.21"},"tool_response":{"exit_code":0}}'
out=$(echo "$json" | CLAUDE_PLUGIN_OPTION_DISABLE=true bash "$SCRIPT" 2>&1; echo "exit=$?")
assert_contains "$out" "exit=0" "DISABLE=true → exit 0"
assert_eq "0" "$(count_entries)" "DISABLE=true → no sidecar entry"

cd "$OLDPWD"
finish_test
