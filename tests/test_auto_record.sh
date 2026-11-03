#!/usr/bin/env bash
VS_TEST_NAME=auto-record
TEST_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$TEST_DIR/assert.sh"
ROOT="$(cd "$TEST_DIR/.." && pwd)"
VS_TMPDIR=$(mktemp -d)
trap 'rm -rf "$VS_TMPDIR"' EXIT
cd "$VS_TMPDIR" || exit 1
for command in 'npm install lodash@4.17.21' 'pip install requests==2.31.0' 'cargo add serde@=1.0.196' 'dotnet add package Newtonsoft.Json --version 13.0.3' 'npm install lodash@latest' 'npm ci' 'cat > out <<EOF
npm install lodash@4.17.21
EOF'; do
  out=$(jq -nc --arg command "$command" '{tool_name:"Bash",tool_input:{command:$command},tool_response:{exit_code:0}}' | bash "$ROOT/scripts/auto-record.sh" 2>&1; echo "exit=$?")
  assert_contains "$out" 'exit=0' 'compatibility post-hook remains nonblocking'
  [[ ! -f .version-sentinel/checks.json ]] || _fail "post-install must not manufacture authorization: $command"
done
mkdir -p .version-sentinel
printf '%s\n' '{"entries":[{"ecosystem":"npm","pkg":"lodash","version":"4.17.21","source":"intentional: old data preserved"}]}' > .version-sentinel/checks.json
cp .version-sentinel/checks.json "$VS_TMPDIR/before.json"
printf '%s\n' '{"tool_name":"Bash","tool_input":{"command":"npm install lodash@4.17.21"},"tool_response":{"exit_code":0}}' | bash "$ROOT/scripts/auto-record.sh"
cmp -s "$VS_TMPDIR/before.json" .version-sentinel/checks.json
assert_eq 0 "$?" 'post-hook cannot overwrite verification evidence'
finish_test
