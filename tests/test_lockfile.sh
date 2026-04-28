#!/usr/bin/env bash
VS_TEST_NAME="lockfile"
source "$(dirname "$0")/assert.sh"

VS_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$VS_TMPDIR"' EXIT

source "$(dirname "$0")/../scripts/lib/lockfile.sh"

# --- acquire creates lockdir ---
vs_lock_acquire "$VS_TMPDIR/test.lock"
assert_eq "0" "$?" "lock acquire succeeds"
assert_file_exists "$VS_TMPDIR/test.lock/held" "lockdir created"

# --- release removes lockdir ---
vs_lock_release "$VS_TMPDIR/test.lock"
result=0; [[ -d "$VS_TMPDIR/test.lock" ]] && result=1
assert_eq "0" "$result" "lockdir removed after release"

# --- acquire with stale lock (>30s) auto-breaks ---
mkdir -p "$VS_TMPDIR/stale.lock"
echo "99999" > "$VS_TMPDIR/stale.lock/held"
touch -t 202601010000 "$VS_TMPDIR/stale.lock/held"
vs_lock_acquire "$VS_TMPDIR/stale.lock"
assert_eq "0" "$?" "stale lock broken and re-acquired"
vs_lock_release "$VS_TMPDIR/stale.lock"

finish_test
