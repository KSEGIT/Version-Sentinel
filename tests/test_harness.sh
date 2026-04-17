#!/usr/bin/env bash
VS_TEST_NAME="harness-smoke"
source "$(dirname "$0")/assert.sh"

assert_eq "a" "a" "trivial equality"
assert_contains "hello world" "world" "substring"
assert_exit_code 0 0 "zero exit"

finish_test
