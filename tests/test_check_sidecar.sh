#!/usr/bin/env bash
VS_TEST_NAME="check-sidecar"
FIXTURES="$(dirname "$0")/fixtures"
source "$(dirname "$0")/assert.sh"

VS_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$VS_TMPDIR"' EXIT

SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/scripts/check-sidecar.sh"

# No sidecar → block (exit 2)
cd "$VS_TMPDIR"
stderr=$(bash "$SCRIPT" npm lodash 4.17.21 2>&1 >/dev/null; echo "exit=$?")
assert_contains "$stderr" "BLOCKED" "block stderr contains BLOCKED"
assert_contains "$stderr" "lodash" "block stderr contains pkg name"
assert_contains "$stderr" "/vs-record" "block stderr tells Claude about /vs-record"
assert_contains "$stderr" "exit=2" "missing entry → exit 2"

# Fresh sidecar entry → allow (exit 0)
mkdir -p "$VS_TMPDIR/.version-sentinel"
cat > "$VS_TMPDIR/.version-sentinel/checks.json" <<EOF
{"entries":[{"ecosystem":"npm","pkg":"lodash","version":"4.17.21","source":"https://x","checkedAt":"$(date -u +%Y-%m-%dT%H:%M:%SZ)"}]}
EOF
out=$(bash "$SCRIPT" npm lodash 4.17.21 2>&1; echo "exit=$?")
assert_contains "$out" "exit=0" "fresh entry → exit 0"

# VS_DISABLE bypasses
rm -rf "$VS_TMPDIR/.version-sentinel"
out=$(VS_DISABLE=1 bash "$SCRIPT" npm lodash 4.17.21 2>&1; echo "exit=$?")
assert_contains "$out" "exit=0" "VS_DISABLE=1 → exit 0 regardless"

cd "$OLDPWD"
finish_test
