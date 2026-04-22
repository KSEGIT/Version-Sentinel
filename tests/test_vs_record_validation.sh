#!/usr/bin/env bash
# Tests enhanced arg validation in scripts/vs-record.sh.
set -u
VS_TEST_NAME="vs-record-validation"
source "$(dirname "$0")/assert.sh"

VS_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$VS_TMPDIR"' EXIT
SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/scripts/vs-record.sh"

cd "$VS_TMPDIR"

# Unknown ecosystem → exit 1, stderr mentions "unknown ecosystem"
err=$(bash "$SCRIPT" bogus lodash 1.0.0 "https://x" 2>&1 >/dev/null; echo "exit=$?")
assert_contains "$err" "exit=1" "unknown ecosystem → exit 1"
assert_contains "$err" "unknown ecosystem" "unknown ecosystem → stderr mentions unknown ecosystem"

# Empty version → exit 1, stderr mentions "invalid version"
err=$(bash "$SCRIPT" npm lodash "" "https://x" 2>&1 >/dev/null; echo "exit=$?")
assert_contains "$err" "exit=1" "empty version → exit 1"
assert_contains "$err" "invalid version" "empty version → stderr mentions invalid version"

# Whitespace-only version → exit 1
err=$(bash "$SCRIPT" npm lodash "   " "https://x" 2>&1 >/dev/null; echo "exit=$?")
assert_contains "$err" "exit=1" "whitespace version → exit 1"
assert_contains "$err" "invalid version" "whitespace version → stderr mentions invalid version"

# Version with embedded space → exit 1
err=$(bash "$SCRIPT" npm lodash "1.0 .0" "https://x" 2>&1 >/dev/null; echo "exit=$?")
assert_contains "$err" "exit=1" "version w/ space → exit 1"
assert_contains "$err" "invalid version" "version w/ space → stderr mentions invalid version"

# Version with embedded tab → exit 1
err=$(bash "$SCRIPT" npm lodash $'1.0\t0' "https://x" 2>&1 >/dev/null; echo "exit=$?")
assert_contains "$err" "exit=1" "version w/ tab → exit 1"
assert_contains "$err" "invalid version" "version w/ tab → stderr mentions invalid version"

# Package with '/' but not npm-scoped → exit 1
err=$(bash "$SCRIPT" pip foo/bar 1.0.0 "https://x" 2>&1 >/dev/null; echo "exit=$?")
assert_contains "$err" "exit=1" "non-npm slash pkg → exit 1"
assert_contains "$err" "invalid package name" "non-npm slash pkg → stderr mentions invalid package name"

# npm '/' without @scope prefix → still invalid
err=$(bash "$SCRIPT" npm foo/bar 1.0.0 "https://x" 2>&1 >/dev/null; echo "exit=$?")
assert_contains "$err" "exit=1" "npm unscoped slash → exit 1"
assert_contains "$err" "invalid package name" "npm unscoped slash → stderr mentions invalid package name"

# Valid npm scoped package → accepted (no validation-exit-1)
out=$(bash "$SCRIPT" npm "@scope/name" 1.0.0 "https://www.npmjs.com/package/@scope/name" 2>&1; echo "exit=$?")
assert_contains "$out" "exit=0" "npm @scope/name accepted"
assert_contains "$out" "recorded" "npm @scope/name → recorded message"

cd "$OLDPWD"
finish_test
