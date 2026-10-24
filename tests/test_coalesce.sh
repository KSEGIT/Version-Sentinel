#!/usr/bin/env bash
VS_TEST_NAME="coalesce"
source "$(dirname "$0")/assert.sh"

# Keep the paused-owner and marker fixtures independent of the caller's timing.
VS_LOCK_TIMEOUT=5
VS_LOCK_STALE_SEC=30
VS_COALESCE_TTL=10
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

wait_for_file() {
  local path="$1" attempts=0
  while [[ ! -f "$path" ]]; do
    if (( attempts >= 500 )); then
      echo "FAIL [$VS_TEST_NAME]: timed out waiting for $path" >&2
      return 1
    fi
    attempts=$((attempts + 1))
    sleep 0.01
  done
}

race_lock="$VS_TMPDIR/.vs_coal_npm_lodash_4.17.21.lock"
race_marker="$VS_TMPDIR/.vs_coal_npm_lodash_4.17.21"
acquire_contender() (
  # Keep the real mkdir, but pause its winner before held is published. The
  # parent releases it only after the other worker has attempted the same lock.
  mkdir() {
    if [[ "$1" != "$race_lock" ]]; then
      command mkdir "$@"
      return $?
    fi
    if command mkdir "$@"; then
      : > "$VS_TMPDIR/owner-ready"
      wait_for_file "$VS_TMPDIR/publish-owner"
      return $?
    fi
    : > "$VS_TMPDIR/contender-ready"
    return 1
  }

  : > "$VS_TMPDIR/worker-$1-ready"
  wait_for_file "$VS_TMPDIR/start-race" || exit 1
  coalesce_acquire "$VS_TMPDIR" "npm" "lodash" "4.17.21"
)

acquire_contender 1 &
pid1=$!
acquire_contender 2 &
pid2=$!
wait_for_file "$VS_TMPDIR/worker-1-ready"
assert_eq "0" "$?" "first concurrent worker is ready"
wait_for_file "$VS_TMPDIR/worker-2-ready"
assert_eq "0" "$?" "second concurrent worker is ready"
: > "$VS_TMPDIR/start-race"
wait_for_file "$VS_TMPDIR/owner-ready"
assert_eq "0" "$?" "one concurrent worker creates the lock"
wait_for_file "$VS_TMPDIR/contender-ready"
assert_eq "0" "$?" "the other worker contends before owner publication"
result=0; [[ -f "$race_marker" ]] && result=1
assert_eq "0" "$result" "marker is not written before the lock owner proceeds"
: > "$VS_TMPDIR/publish-owner"
# Wait and capture exit codes
wait "$pid1"
exit1=$?
wait "$pid2"
exit2=$?
# Report both worker statuses if the expected {0, 1} result is missing.
case "$exit1:$exit2" in
  0:1|1:0) ;;
  *) _fail "concurrent acquire: expected exit codes 0 and 1, got $exit1 and $exit2" ;;
esac
assert_file_exists "$race_marker" "concurrent winner leaves its in-flight marker"
coalesce_acquire "$VS_TMPDIR" "npm" "lodash" "4.17.21"
assert_eq "1" "$?" "concurrent winner's fresh marker rejects another acquire"

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
