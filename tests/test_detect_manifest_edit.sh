#!/usr/bin/env bash
VS_TEST_NAME="detect-manifest-edit"
TESTS_DIR="$(cd "$(dirname "$0")" && pwd)"
FIXTURES="$TESTS_DIR/fixtures"
source "$TESTS_DIR/assert.sh"

VS_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$VS_TMPDIR"' EXIT

SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/scripts/detect-manifest-edit.sh"

cd "$VS_TMPDIR"
cat > package.json <<EOF
{
  "name": "fixture",
  "version": "1.0.0",
  "dependencies": {
    "express": "4.19.2"
  }
}
EOF

substitute() {
  sed "s|{{CWD}}|$VS_TMPDIR|g" "$1"
}

# Case 1: Edit adds lodash → block
input=$(substitute "$FIXTURES/edit_input_add_lodash.json")
result=$(echo "$input" | bash "$SCRIPT" 2>&1; echo "exit=$?")
assert_contains "$result" "BLOCKED" "edit-add: blocked"
assert_contains "$result" "lodash" "edit-add: names pkg"
assert_contains "$result" "exit=2" "edit-add: exit 2"

# Case 2: Write new content w/ lodash → block
input=$(substitute "$FIXTURES/write_input_new_package.json")
result=$(echo "$input" | bash "$SCRIPT" 2>&1; echo "exit=$?")
assert_contains "$result" "BLOCKED" "write: blocked"
assert_contains "$result" "lodash" "write: names pkg"

# Case 3: MultiEdit bumps express → block
input=$(substitute "$FIXTURES/multiedit_input_bump.json")
result=$(echo "$input" | bash "$SCRIPT" 2>&1; echo "exit=$?")
assert_contains "$result" "BLOCKED" "multiedit-bump: blocked"
assert_contains "$result" "express" "multiedit-bump: names pkg"

# Case 4: Edit on a non-manifest file → pass silently
cat > README.md <<EOF
# Demo
EOF
input='{"tool_name":"Edit","tool_input":{"file_path":"'"$VS_TMPDIR"'/README.md","old_string":"# Demo","new_string":"# Demo2","replace_all":false}}'
result=$(echo "$input" | bash "$SCRIPT" 2>&1; echo "exit=$?")
assert_contains "$result" "exit=0" "non-manifest: exit 0"

# Case 5: VS_DISABLE bypass
input=$(substitute "$FIXTURES/edit_input_add_lodash.json")
result=$(echo "$input" | VS_DISABLE=1 bash "$SCRIPT" 2>&1; echo "exit=$?")
assert_contains "$result" "exit=0" "VS_DISABLE: exit 0"

cd "$OLDPWD"
finish_test
