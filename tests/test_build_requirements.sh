#!/usr/bin/env bash
# Build backends are registry dependencies and require the same online evidence.
VS_TEST_NAME="build-requirements"
TESTS_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPTS="$(cd "$TESTS_DIR/../scripts" && pwd)"
source "$TESTS_DIR/assert.sh"
source "$TESTS_DIR/registry-fixture.sh"
VS_TMPDIR=$(mktemp -d)
trap 'rm -rf "$VS_TMPDIR"' EXIT
cd "$VS_TMPDIR" || exit 1
registry_fixture_setup
printf '%s\n' '[project]' 'name = "demo"' > pyproject.toml
bash "$SCRIPTS/check-versions.sh" >/dev/null 2>&1
post=$'[project]\nname = "demo"\n[build-system]\nrequires = ["nonexistent-build-backend==99.99.99"]\n'
result=$(jq -nc --arg content "$post" '{tool_name:"Write",tool_input:{file_path:"pyproject.toml",content:$content}}' | bash "$SCRIPTS/detect-manifest-edit.sh" 2>&1); status=$?
assert_exit_code 2 "$status" 'unverified build backend addition blocks'
assert_contains "$result" 'nonexistent-build-backend' 'blocked build backend named'
post=$'[project]\nname = "demo"\n[build-system]\nrequires = ["requests==2.31.0"]\n'
result=$(jq -nc --arg content "$post" '{tool_name:"Write",tool_input:{file_path:"pyproject.toml",content:$content}}' | bash "$SCRIPTS/detect-manifest-edit.sh" 2>&1); status=$?
assert_exit_code 2 "$status" 'existing build package still needs online record'
bash "$SCRIPTS/vs-record.sh" pyproject requests 2.31.0 https://pypi.org/project/requests/ >/dev/null 2>&1
result=$(jq -nc --arg content "$post" '{tool_name:"Write",tool_input:{file_path:"pyproject.toml",content:$content}}' | bash "$SCRIPTS/detect-manifest-edit.sh" 2>&1); status=$?
assert_exit_code 0 "$status" 'build backend addition allowed after online record'
printf '%s' "$post" > pyproject.toml
result=$(bash "$SCRIPTS/check-versions.sh" 2>&1); status=$?
assert_exit_code 0 "$status" 'existing build backend can be audited'
assert_contains "$result" 'requests' 'build backend appears in audit report'
VS_FIXTURE_NETWORK_FAIL=1 bash "$SCRIPTS/check-versions.sh" >/dev/null 2>&1
assert_exit_code 2 "$?" 'build backend lookup failure fails audit'
for declaration in 'requires = "requests==2.31.0"' 'requires = [false]'; do
  printf '%s\n' '[build-system]' "$declaration" | bash "$SCRIPTS/audit-state.sh" validate-content pyproject.toml >/dev/null 2>&1
  assert_exit_code 2 "$?" 'malformed build requirement list rejects'
done
finish_test
