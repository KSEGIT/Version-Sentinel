#!/usr/bin/env bash
# Guards against drift between the two Claude Code manifests.
#
# The repo ships plugin.json at the root and .claude-plugin/plugin.json.
# Claude Code reads the .claude-plugin/ copy, but release-please stamps
# $.version into both and the README/AGENTS.md document both as "the"
# manifest. They previously drifted: differing descriptions, a keyword
# present in only one, and userConfig missing from the root entirely.
set -u
VS_TEST_NAME="manifest-parity"
source "$(dirname "$0")/assert.sh"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
A="$ROOT/plugin.json"
B="$ROOT/.claude-plugin/plugin.json"

assert_file_exists "$A" "root manifest present"
assert_file_exists "$B" ".claude-plugin manifest present"

assert_eq "0" "$(jq empty "$A" >/dev/null 2>&1; echo $?)" "root manifest is valid JSON"
assert_eq "0" "$(jq empty "$B" >/dev/null 2>&1; echo $?)" ".claude-plugin manifest is valid JSON"

# Deep JSON equality — formatting may differ, content must not.
if ! diff <(jq -S . "$A" 2>/dev/null) <(jq -S . "$B" 2>/dev/null) >/dev/null 2>&1; then
  _fail "manifests differ; sync them: $(diff <(jq -S . "$A") <(jq -S . "$B") | head -20 | tr '\n' ' ')"
fi

# Spot-check the fields that actually drifted before, so a future
# regression names the offending key rather than dumping a whole diff.
for key in description version userConfig keywords; do
  assert_eq "$(jq -Sc ".$key" "$A" 2>/dev/null)" "$(jq -Sc ".$key" "$B" 2>/dev/null)" \
    "manifests agree on .$key"
done

finish_test
