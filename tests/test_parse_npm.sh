#!/usr/bin/env bash
VS_TEST_NAME="parse-npm"
FIXTURES="$(dirname "$0")/fixtures"
source "$(dirname "$0")/assert.sh"
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "$SCRIPT_DIR/scripts/lib/parse-manifest.sh"

out=$(parse_npm "$FIXTURES/package.json" | sort)
expected=$(printf '%s\n' \
  "lodash	4.17.21" \
  "express	4.19.2" \
  "jest	29.7.0" \
  "react	18.0.0" \
  "fsevents	2.3.3" | sort)
assert_eq "$expected" "$out" "npm all 4 dep sections parsed, version prefixes stripped"

# Empty manifest → empty output, exit 0
out=$(parse_npm "$FIXTURES/package_no_deps.json")
assert_eq "" "$out" "no deps → empty"

# Missing file → empty output, exit 0 (fail-open)
out=$(parse_npm /nope/nonexistent.json 2>/dev/null)
assert_eq "" "$out" "missing file → empty (fail open)"

finish_test
