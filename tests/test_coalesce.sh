#!/usr/bin/env bash
VS_TEST_NAME="coalesce"
source "$(dirname "$0")/assert.sh"

source "$(dirname "$0")/../scripts/lib/coalesce.sh"

VS_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$VS_TMPDIR"' EXIT

# --- first acquire succeeds ---
coalesce_acquire "$VS_TMPDIR" "npm" "lodash" "4.17.21"
assert_eq "0" "$?" "first acquire succeeds"

# --- second acquire for same pkg fails (in-flight) ---
coalesce_acquire "$VS_TMPDIR" "npm" "lodash" "4.17.21"
assert_eq "1" "$?" "duplicate acquire fails"

# --- different package still succeeds ---
coalesce_acquire "$VS_TMPDIR" "npm" "express" "4.18.0"
assert_eq "0" "$?" "different package acquire succeeds"

# --- release allows re-acquire ---
coalesce_release "$VS_TMPDIR" "npm" "lodash" "4.17.21"
coalesce_acquire "$VS_TMPDIR" "npm" "lodash" "4.17.21"
assert_eq "0" "$?" "re-acquire after release succeeds"
coalesce_release "$VS_TMPDIR" "npm" "lodash" "4.17.21"

# --- stale marker (>10s) auto-cleared ---
coalesce_acquire "$VS_TMPDIR" "npm" "stale-pkg" "1.0.0"
marker_file="$VS_TMPDIR/.vs_coal_npm_stale-pkg_1.0.0"
touch -t 202601010000 "$marker_file"
coalesce_acquire "$VS_TMPDIR" "npm" "stale-pkg" "1.0.0"
assert_eq "0" "$?" "stale marker auto-cleared"
coalesce_release "$VS_TMPDIR" "npm" "stale-pkg" "1.0.0"

finish_test
