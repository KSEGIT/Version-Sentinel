#!/usr/bin/env bash
# Shared assertions. Source this from each test script.
set -u

VS_TEST_FAILED=0
VS_TEST_NAME="${VS_TEST_NAME:-unnamed}"

_fail() {
  echo "FAIL [$VS_TEST_NAME]: $1" >&2
  VS_TEST_FAILED=1
}

assert_eq() {
  # assert_eq <expected> <actual> <label>
  if [[ "$1" != "$2" ]]; then
    _fail "$3: expected '$1', got '$2'"
  fi
}

assert_contains() {
  # assert_contains <haystack> <needle> <label>
  if [[ "$1" != *"$2"* ]]; then
    _fail "$3: string does not contain '$2'. Full: $1"
  fi
}

assert_exit_code() {
  # assert_exit_code <expected> <actual> <label>
  assert_eq "$1" "$2" "$3 (exit code)"
}

assert_file_exists() {
  # assert_file_exists <path> <label>
  if [[ ! -f "$1" ]]; then
    _fail "$2: file missing: $1"
  fi
}

finish_test() {
  if [[ "$VS_TEST_FAILED" -eq 0 ]]; then
    echo "PASS [$VS_TEST_NAME]"
  fi
  return "$VS_TEST_FAILED"
}
