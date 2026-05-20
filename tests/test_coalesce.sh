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

# --- concurrent acquire test: exactly one succeeds ---
coalesce_release "$VS_TMPDIR" "npm" "lodash" "4.17.21"
# Background two concurrent acquire attempts
(coalesce_acquire "$VS_TMPDIR" "npm" "lodash" "4.17.21"; exit $?) &
pid1=$!
(coalesce_acquire "$VS_TMPDIR" "npm" "lodash" "4.17.21"; exit $?) &
pid2=$!
# Wait and capture exit codes
wait $pid1
exit1=$?
wait $pid2
exit2=$?
# Exactly one should succeed (exit 0), the other should fail (exit 1)
sum=$((exit1 + exit2))
assert_eq "1" "$sum" "concurrent acquire: exactly one succeeds (exit codes sum to 1)"

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
