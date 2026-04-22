#!/usr/bin/env bash
# Tests scripts/prereq-check.sh: exits 0, warns when tools missing, silent when disabled.
set -u
VS_TEST_NAME="prereq-check"
source "$(dirname "$0")/assert.sh"

SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/scripts/prereq-check.sh"

# Case 1: normal PATH → exit 0 (warnings optional depending on host tool availability)
out=$(bash "$SCRIPT" 2>&1; echo "exit=$?")
assert_contains "$out" "exit=0" "normal PATH → exit 0"

# Case 2: sanitized PATH without jq → exit 0 AND stderr mentions "jq not found".
# Strategy: invoke bash (and the script) by absolute path so the interpreter itself
# does not need to resolve through PATH. The child process inherits the sanitized
# PATH, so `command -v jq` returns empty and the warn branch triggers.
fakebin=$(mktemp -d)
BASH_ABS=$(command -v bash)
trap 'rm -rf "$fakebin"' EXIT

err=$(PATH="$fakebin" "$BASH_ABS" "$SCRIPT" 2>&1 >/dev/null; echo "exit=$?")
assert_contains "$err" "exit=0" "sanitized PATH → still exit 0"
# Case-insensitive match for "jq not found".
lower=$(echo "$err" | tr '[:upper:]' '[:lower:]')
assert_contains "$lower" "jq not found" "sanitized PATH → stderr mentions 'jq not found'"

# Case 3: CLAUDE_PLUGIN_OPTION_DISABLE=true → exit 0, silent (no warnings).
err=$(CLAUDE_PLUGIN_OPTION_DISABLE=true bash "$SCRIPT" 2>&1 >/dev/null; echo "exit=$?")
assert_contains "$err" "exit=0" "DISABLE=true → exit 0"
# Ensure no "version-sentinel:" warnings leaked on stderr.
if echo "$err" | grep -q 'version-sentinel:'; then
  _fail "DISABLE=true should be silent; got: $err"
fi

finish_test
