#!/usr/bin/env bash
VS_TEST_NAME="parse-pip"
FIXTURES="$(dirname "$0")/fixtures"
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "$(dirname "$0")/assert.sh"
source "$SCRIPT_DIR/scripts/lib/parse-manifest.sh"

# Basic file
out=$(parse_pip "$FIXTURES/requirements.txt" | sort)
expected=$(printf '%s\n' "flask	2.3.0" "numpy	1.26.0" "requests	2.31.0" | sort)
assert_eq "$expected" "$out" "pip basic"

# Tricky file
out=$(parse_pip "$FIXTURES/requirements_tricky.txt" | sort)
expected=$(printf '%s\n' "PyYAML	6.0" "click	8.1.7" | sort)
assert_eq "$expected" "$out" "pip tricky (comments/includes/editable/range skipped)"

finish_test
