#!/usr/bin/env bash
VS_TEST_NAME=install-command-compat
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/tests/assert.sh"
VS_TMPDIR=$(mktemp -d)
trap 'rm -rf "$VS_TMPDIR"' EXIT
source "$ROOT/tests/registry-fixture.sh"
registry_fixture_setup
mkdir -p "$VS_TMPDIR/project" "$VS_TMPDIR/other"
cd "$VS_TMPDIR/project" || exit 1
printf '{}' > package.json
printf '{}' > ../other/package.json
hook() {
  jq -nc --arg cwd "$PWD" --arg cmd "$1" '{tool_name:"Bash",cwd:$cwd,tool_input:{command:$cmd}}' |
    bash "$ROOT/scripts/detect-install-cmd.sh" 2>&1
}
for cmd in 'yarn --frozen-lockfile' 'yarn --immutable' 'yarn --cwd ../other'; do
  output=$(hook "$cmd"); status=$?
  assert_exit_code 2 "$status" "implicit Yarn install requires audit: $cmd ($output)"
done
for cmd in 'yarn --version' 'yarn -v' 'yarn --help' 'yarn -h' 'yarn --cwd ../other --version'; do
  output=$(hook "$cmd"); status=$?
  assert_exit_code 0 "$status" "Yarn read-only flags remain usable: $cmd ($output)"
done
bash "$ROOT/scripts/check-versions.sh" >/dev/null || exit 1
bash "$ROOT/scripts/vs-record.sh" npm lodash 4.17.21 https://www.npmjs.com/package/lodash >/dev/null || exit 1
for cmd in 'yarn --frozen-lockfile' 'yarn --immutable' \
  'npm install lodash@4.17.21 2>&1' 'npm install lodash@4.17.21 > log' \
  'npm install lodash@4.17.21 >log' 'npm install lodash@4.17.21 2>error.log' \
  'npm install lodash@4.17.21 &>log' 'npm install lodash@4.17.21 &>>log' \
  'npm install lodash@4.17.21 2>&1 >"log with spaces"'; do
  output=$(hook "$cmd"); status=$?
  assert_exit_code 0 "$status" "verified install preserves redirect semantics: $cmd ($output)"
done
output=$(hook 'yarn --cwd ../other'); status=$?
assert_exit_code 2 "$status" 'Yarn implicit cwd install cannot borrow current audit'
output=$(hook $'cd ../other && npm \\\ninstall lodash@4.17.21 2>&1'); status=$?
assert_exit_code 2 "$status" 'line continuation cannot lose the dependency command cwd'
for cmd in 'yarn --verbose add unrecorded@99.99.99' 'yarn --version add unrecorded@99.99.99' 'npm install 2 >log' 'npm install "2>&1"' 'npm install ">log"' \
  'npm install unrecorded@99.99.99 2>&1' 'npm install lodash@4.17.21 <<EOF' \
  'npm install lodash@4.17.21 >$(printf log)'; do
  output=$(hook "$cmd"); status=$?
  assert_exit_code 2 "$status" "redirects cannot hide unchecked package or unsupported syntax: $cmd ($output)"
done
finish_test
