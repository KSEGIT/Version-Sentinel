#!/usr/bin/env bash
VS_TEST_NAME="check-sidecar"
FIXTURES="$(dirname "$0")/fixtures"
TEST_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$TEST_DIR/assert.sh"
source "$TEST_DIR/registry-fixture.sh"

VS_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$VS_TMPDIR"' EXIT

SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/scripts/check-sidecar.sh"

# No sidecar → block (exit 2)
registry_fixture_setup
cd "$VS_TMPDIR"
stderr=$(bash "$SCRIPT" npm lodash 4.17.21 2>&1 >/dev/null; echo "exit=$?")
assert_contains "$stderr" "BLOCKED" "block stderr contains BLOCKED"
assert_contains "$stderr" "lodash" "block stderr contains pkg name"
assert_contains "$stderr" "/vs-record" "block stderr tells Claude about /vs-record"
assert_contains "$stderr" "exit=2" "missing entry → exit 2"

# Legacy URL-only entry must not authorize dependency work.
mkdir -p "$VS_TMPDIR/.version-sentinel"
printf '{"entries":[{"ecosystem":"npm","pkg":"lodash","version":"4.17.21","source":"https://x","checkedAt":"%s"}]}' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > .version-sentinel/checks.json
out=$(bash "$SCRIPT" npm lodash 4.17.21 2>&1; echo "exit=$?")
assert_contains "$out" "exit=2" "legacy URL-only entry blocks"

# Successful online verification writes an authorizing record.
bash "${SCRIPT%/*}/vs-record.sh" npm lodash 4.17.21 https://www.npmjs.com/package/lodash >/dev/null
out=$(bash "$SCRIPT" npm lodash 4.17.21 2>&1; echo "exit=$?")
assert_contains "$out" "exit=0" "fresh verified entry allows"

# VS_DISABLE bypasses
rm -rf "$VS_TMPDIR/.version-sentinel"
out=$(VS_DISABLE=1 bash "$SCRIPT" npm lodash 4.17.21 2>&1; echo "exit=$?")
assert_contains "$out" "exit=0" "VS_DISABLE=1 → exit 0 regardless"

cd "$OLDPWD"
finish_test
