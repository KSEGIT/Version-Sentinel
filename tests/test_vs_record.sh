#!/usr/bin/env bash
VS_TEST_NAME="vs-record"
source "$(dirname "$0")/assert.sh"

VS_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$VS_TMPDIR"' EXIT
SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/scripts/vs-record.sh"

cd "$VS_TMPDIR"

# Valid URL → writes entry
out=$(bash "$SCRIPT" npm lodash 4.17.21 "https://www.npmjs.com/package/lodash" 2>&1; echo "exit=$?")
assert_contains "$out" "exit=0" "valid URL → success"
count=$(jq '.entries | length' .version-sentinel/checks.json)
assert_eq "1" "$count" "one entry written"
src=$(jq -r '.entries[0].source' .version-sentinel/checks.json)
assert_eq "https://www.npmjs.com/package/lodash" "$src" "source URL preserved"

# Intentional reason → accepted
out=$(bash "$SCRIPT" npm lodash 4.17.21 "intentional: CVE lock" 2>&1; echo "exit=$?")
assert_contains "$out" "exit=0" "intentional: accepted"

# Dedupe: same pkg new version overwrites
out=$(bash "$SCRIPT" npm lodash 5.0.0 "https://www.npmjs.com/package/lodash" 2>&1; echo "exit=$?")
count=$(jq '.entries | length' .version-sentinel/checks.json)
assert_eq "1" "$count" "dedupe: still 1 entry"
ver=$(jq -r '.entries[0].version' .version-sentinel/checks.json)
assert_eq "5.0.0" "$ver" "dedupe: new version wins"

# Invalid source → rejected
out=$(bash "$SCRIPT" npm lodash 4.17.21 "just trust me" 2>&1; echo "exit=$?")
assert_contains "$out" "exit=1" "invalid source: exit 1"
assert_contains "$out" "http" "rejection message mentions expected format"

# Missing args → rejected
out=$(bash "$SCRIPT" npm lodash 2>&1; echo "exit=$?")
assert_contains "$out" "exit=1" "missing args: exit 1"

cd "$OLDPWD"
finish_test
