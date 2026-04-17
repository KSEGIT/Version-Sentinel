#!/usr/bin/env bash
VS_TEST_NAME="sidecar"
source "$(dirname "$0")/assert.sh"
source "$(dirname "$0")/../scripts/lib/sidecar.sh"

TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

# --- sidecar_read returns entries from a valid file ---
cp fixtures/sidecar_one_entry.json "$TMPDIR/checks.json"
out=$(sidecar_read "$TMPDIR/checks.json")
assert_contains "$out" "lodash" "read returns entries"

# --- sidecar_read on missing file returns empty entries array ---
out=$(sidecar_read "$TMPDIR/nope.json")
assert_contains "$out" '"entries":[]' "missing file → empty"

# --- sidecar_read on corrupt file returns empty + warns ---
echo "not json" > "$TMPDIR/corrupt.json"
out=$(sidecar_read "$TMPDIR/corrupt.json" 2>/dev/null)
assert_contains "$out" '"entries":[]' "corrupt file → empty"

# --- sidecar_find_fresh: found within window ---
cp fixtures/sidecar_one_entry.json "$TMPDIR/checks.json"
VS_NOW_OVERRIDE="2026-04-16T14:00:00Z" \
  result=$(sidecar_find_fresh "$TMPDIR/checks.json" npm lodash 4.17.21 24; echo "exit=$?")
assert_contains "$result" "exit=0" "fresh entry hit"

# --- sidecar_find_fresh: stale ---
VS_NOW_OVERRIDE="2026-04-18T10:00:01Z" \
  result=$(sidecar_find_fresh "$TMPDIR/checks.json" npm lodash 4.17.21 24; echo "exit=$?")
assert_contains "$result" "exit=1" "stale entry missed"

# --- sidecar_find_fresh: different version missed ---
VS_NOW_OVERRIDE="2026-04-16T14:00:00Z" \
  result=$(sidecar_find_fresh "$TMPDIR/checks.json" npm lodash 5.0.0 24; echo "exit=$?")
assert_contains "$result" "exit=1" "different version missed"

# --- sidecar_write_entry dedupe ---
cp fixtures/sidecar_empty.json "$TMPDIR/checks.json"
sidecar_write_entry "$TMPDIR/checks.json" npm lodash 4.17.21 \
  "https://www.npmjs.com/package/lodash" "2026-04-16T10:00:00Z"
sidecar_write_entry "$TMPDIR/checks.json" npm lodash 4.18.0 \
  "https://www.npmjs.com/package/lodash" "2026-04-16T11:00:00Z"
count=$(jq '.entries | length' "$TMPDIR/checks.json")
assert_eq "1" "$count" "dedupe: same (ecosystem,pkg) keeps only one entry"
version=$(jq -r '.entries[0].version' "$TMPDIR/checks.json")
assert_eq "4.18.0" "$version" "dedupe: last-write-wins"

# --- sidecar_write_entry auto-creates .gitignore ---
GITIGNORE="$TMPDIR/.gitignore"
assert_file_exists "$GITIGNORE" "auto-gitignore created"
content=$(cat "$GITIGNORE")
assert_contains "$content" "*" "gitignore contains *"
assert_contains "$content" "!.gitignore" "gitignore re-includes itself"

finish_test
