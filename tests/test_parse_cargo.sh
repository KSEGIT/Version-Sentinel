#!/usr/bin/env bash
VS_TEST_NAME="parse-cargo"
FIXTURES="$(dirname "$0")/fixtures"
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "$(dirname "$0")/assert.sh"
source "$SCRIPT_DIR/scripts/lib/parse-manifest.sh"

out=$(parse_cargo "$FIXTURES/Cargo.toml" | sort)
expected=$(printf '%s\n' \
  "cc	1.0.83" \
  "criterion	0.5.1" \
  "serde	1.0.196" \
  "tokio	1.36.0" | sort)
assert_eq "$expected" "$out" "cargo all 3 dep sections, path-deps skipped"

tmp=$(mktemp)
printf '%s\n' \
  '[package]' 'name = "demo"' 'version = "0.1.0"' \
  '[dependencies]' \
  'registry-dep = {}' \
  'wildcard-dep = "*"' \
  'local = { path = "../local" }' \
  'shared = { workspace = true }' > "$tmp"
out=$(parse_cargo "$tmp" | sort)
expected=$(printf '%s\n' \
  $'registry-dep\t__version_sentinel_unpinned__' \
  $'wildcard-dep\t__version_sentinel_unpinned__' | sort)
assert_eq "$expected" "$out" "cargo registry tables without versions are unpinned; path/workspace refs skipped"
rm -f "$tmp"

finish_test
