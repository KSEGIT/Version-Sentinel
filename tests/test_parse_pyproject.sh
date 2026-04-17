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

finish_test
