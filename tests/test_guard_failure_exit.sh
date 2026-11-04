#!/usr/bin/env bash
VS_TEST_NAME=guard-failure-exit
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/tests/assert.sh"
VS_TMPDIR=$(mktemp -d)
trap 'rm -rf "$VS_TMPDIR"' EXIT
cd "$VS_TMPDIR" || exit 1
# Python's JSON decoder raises RecursionError before it can inspect this edit.
# A hook runtime failure must be a hard block, never the host's warning status.
result=$(python3 -c 'print("{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"package.json\",\"content\":\"{}\"},\"extra\":"+"["*2000+"0"+"]"*2000+"}")' |
  bash "$ROOT/scripts/detect-manifest-edit.sh" 2>&1); status=$?
assert_exit_code 2 "$status" 'uncaught inspection error maps to hard block'
assert_contains "$result" 'BLOCKED' 'runtime failure explains hard block'
cp -R "$ROOT/scripts" "$VS_TMPDIR/plugin-scripts"
rm "$VS_TMPDIR/plugin-scripts/lib/path_helpers.py"
result=$(printf '%s' '{"tool_name":"Write","tool_input":{"file_path":"package.json","content":"{}"}}' |
  bash "$VS_TMPDIR/plugin-scripts/detect-manifest-edit.sh" 2>&1); status=$?
assert_exit_code 2 "$status" 'broken internal prerequisite maps to hard block'
assert_contains "$result" 'BLOCKED' 'broken script import explains hard block'

finish_test
