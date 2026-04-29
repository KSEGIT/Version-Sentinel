#!/usr/bin/env bash
VS_TEST_NAME="circuit-breaker"
source "$(dirname "$0")/assert.sh"

source "$(dirname "$0")/../scripts/lib/circuit-breaker.sh"

VS_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$VS_TMPDIR"' EXIT

# --- starts closed, allows calls ---
cb_reset "$VS_TMPDIR"
cb_is_open "$VS_TMPDIR" "npm"
assert_eq "1" "$?" "initially closed (not open)"

# --- opens after threshold failures ---
VS_CB_THRESHOLD=3
cb_reset "$VS_TMPDIR"
cb_record_failure "$VS_TMPDIR" "npm"
cb_record_failure "$VS_TMPDIR" "npm"
cb_record_failure "$VS_TMPDIR" "npm"
cb_is_open "$VS_TMPDIR" "npm"
assert_eq "0" "$?" "open after 3 failures"

# --- different registries tracked independently ---
cb_is_open "$VS_TMPDIR" "pip"
assert_eq "1" "$?" "pip still closed"

# --- success resets counter ---
cb_reset "$VS_TMPDIR"
cb_record_failure "$VS_TMPDIR" "npm"
cb_record_failure "$VS_TMPDIR" "npm"
cb_record_success "$VS_TMPDIR" "npm"
cb_record_failure "$VS_TMPDIR" "npm"
cb_is_open "$VS_TMPDIR" "npm"
assert_eq "1" "$?" "success resets counter, still closed"

finish_test
