#!/usr/bin/env bash
VS_TEST_NAME="parse-pyproject"
FIXTURES="$(dirname "$0")/fixtures"
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "$(dirname "$0")/assert.sh"
source "$SCRIPT_DIR/scripts/lib/parse-manifest.sh"

out=$(parse_pyproject "$FIXTURES/pyproject.toml" | sort)
expected=$(printf '%s\n' \
  "click	8.1.7" \
  "flask	3.0.0" \
  "mypy	1.8.0" \
  "pydantic	2.5.3" \
  "pytest	8.0.0" \
  "requests	2.31.0" | sort)
assert_eq "$expected" "$out" "pyproject all sources"

tmp=$(mktemp)
printf '%s\n' \
  '[project]' \
  'dependencies = ["requests", "local @ file:///tmp/local"]' \
  '[tool.poetry.dependencies]' \
  'flask = "*"' \
  'click = { optional = true }' \
  'local = { path = "../local" }' > "$tmp"
out=$(parse_pyproject "$tmp" | sort)
expected=$(printf '%s\n' \
  $'click\t__version_sentinel_unpinned__' \
  $'flask\t__version_sentinel_unpinned__' \
  $'requests\t__version_sentinel_unpinned__' | sort)
assert_eq "$expected" "$out" "pyproject bare registry dependencies are unpinned; direct/path refs skipped"
rm -f "$tmp"

finish_test
