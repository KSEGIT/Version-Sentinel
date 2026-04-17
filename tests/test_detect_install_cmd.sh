#!/usr/bin/env bash
VS_TEST_NAME="detect-install-cmd"
FIXTURES="$(cd "$(dirname "$0")" && pwd)/fixtures"
source "$(dirname "$0")/assert.sh"

VS_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$VS_TMPDIR"' EXIT
SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/scripts/detect-install-cmd.sh"

cd "$VS_TMPDIR"

# Case 1: npm install X@Y with no sidecar → block
result=$(cat "$FIXTURES/bash_npm_install.json" | bash "$SCRIPT" 2>&1; echo "exit=$?")
assert_contains "$result" "BLOCKED" "npm install blocked"
assert_contains "$result" "lodash" "npm install names pkg"

# Case 2: pip install X==Y with no sidecar → block
result=$(cat "$FIXTURES/bash_pip_install.json" | bash "$SCRIPT" 2>&1; echo "exit=$?")
assert_contains "$result" "BLOCKED" "pip install blocked"
assert_contains "$result" "requests" "pip install names pkg"

# Case 3: Unrelated bash command → pass
result=$(echo '{"tool_name":"Bash","tool_input":{"command":"ls -la"}}' | bash "$SCRIPT" 2>&1; echo "exit=$?")
assert_contains "$result" "exit=0" "unrelated cmd: exit 0"

# Case 4: install without version → pass (nothing to verify)
result=$(echo '{"tool_name":"Bash","tool_input":{"command":"npm install lodash"}}' | bash "$SCRIPT" 2>&1; echo "exit=$?")
assert_contains "$result" "exit=0" "no-version install: pass"

# Case 5: fresh sidecar → pass
mkdir -p .version-sentinel
now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
cat > .version-sentinel/checks.json <<EOF
{"entries":[{"ecosystem":"npm","pkg":"lodash","version":"4.17.21","source":"https://x","checkedAt":"$now"}]}
EOF
result=$(cat "$FIXTURES/bash_npm_install.json" | bash "$SCRIPT" 2>&1; echo "exit=$?")
assert_contains "$result" "exit=0" "fresh sidecar: pass"

cd "$OLDPWD"
finish_test
