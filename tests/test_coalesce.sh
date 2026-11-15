#!/usr/bin/env bash
VS_TEST_NAME="coalesce"
source "$(dirname "$0")/assert.sh"

# Keep the paused-owner and marker fixtures independent of the caller's timing.
VS_LOCK_TIMEOUT=5
VS_LOCK_STALE_SEC=30
VS_COALESCE_TTL=10
source "$(dirname "$0")/../scripts/lib/coalesce.sh"

VS_TMPDIR="$(mktemp -d)"
pid1='' pid2=''
cleanup() {
  local pid
  for pid in "$pid1" "$pid2"; do
    [[ -z "$pid" ]] || kill "$pid" 2>/dev/null || :
  done
  rm -rf "$VS_TMPDIR"
}
trap cleanup EXIT

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
acquire_worker() (
  # Give the two workers explicit roles. Only the owner may pause after its
  # successful mkdir, and only the contender may signal a failed mkdir.
  role="$1"
  mkdir() {
    if [[ "$1" != "$race_lock" ]]; then
      command mkdir "$@"
      return $?
    fi
    if command mkdir "$@" 2>> "$VS_TMPDIR/$role.log"; then
      if [[ "$role" == owner ]]; then
        : > "$VS_TMPDIR/owner-ready"
        # The parent owns the release and the bounded wait. A second timer
        # here could expire first, retry mkdir, and impersonate a contender.
        while [[ ! -f "$VS_TMPDIR/publish-owner" ]]; do sleep 0.01; done
      fi
      return 0
    fi
    if [[ "$role" == contender ]]; then
      : > "$VS_TMPDIR/contender-ready"
    fi
    return 1
  }
  coalesce_acquire "$VS_TMPDIR" "npm" "lodash" "4.17.21"
)

wait_for_worker() {
  if ! wait_for_file "$VS_TMPDIR/$1-ready"; then
    # mkdir runs with stderr redirected by the real lock API. Keep the
    # fixture's stage errors available when a worker fails to signal.
    local log
    for log in "$VS_TMPDIR/owner.log" "$VS_TMPDIR/contender.log"; do
      [[ ! -f "$log" ]] || cat "$log" >&2
    done
    exit 1
  fi
}

acquire_worker owner &
pid1=$!
wait_for_worker owner
acquire_worker contender &
pid2=$!
wait_for_worker contender
result=0; [[ -f "$race_lock/held" ]] && result=1
assert_eq "0" "$result" "contender reaches the lock before owner metadata is written"
result=0; [[ -f "$race_marker" ]] && result=1
assert_eq "0" "$result" "marker is not written before the lock owner proceeds"
: > "$VS_TMPDIR/publish-owner"
# Wait and capture exit codes
wait "$pid1"
exit1=$?
pid1=''
wait "$pid2"
exit2=$?
pid2=''
assert_eq "0" "$exit1" "paused owner acquires successfully"
assert_eq "1" "$exit2" "contender rejects the fresh in-flight marker"
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
