#!/usr/bin/env bash
VS_TEST_NAME=registry-shapes
TEST_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$TEST_DIR/.." && pwd)"
source "$TEST_DIR/assert.sh"
source "$TEST_DIR/registry-fixture.sh"
VS_TMPDIR=$(mktemp -d)
trap 'rm -rf "$VS_TMPDIR"' EXIT
registry_fixture_setup
mkdir "$VS_TMPDIR/project"
cd "$VS_TMPDIR/project" || exit 1
export VS_FIXTURE_RESPONSE_FILE="$VS_TMPDIR/response.json"
record() { bash "$ROOT/scripts/vs-record.sh" "$@" 2>&1; echo "exit=$?"; }

# An epoch is part of an exact PEP 440 version, not an exclusion selector.
printf '%s\n' '{"info":{"version":"1!2.0"},"releases":{"1!2.0":[{"yanked":false}]}}' > "$VS_FIXTURE_RESPONSE_FILE"
for eco in pip pyproject; do
  out=$(record "$eco" requests '1!2.0' https://pypi.org/project/requests/)
  assert_contains "$out" 'exit=0' "$eco exact epoch version is online verified"
  out=$(bash "$ROOT/scripts/check-sidecar.sh" "$eco" requests '1!2.0' 2>&1; echo "exit=$?")
  assert_contains "$out" 'exit=0' "$eco exact epoch record authorizes"
done
printf '%s\n' '{"dist-tags":{"latest":"1!2.0"},"versions":{"1!2.0":{}}}' > "$VS_FIXTURE_RESPONSE_FILE"
assert_contains "$(record npm lodash '1!2.0' https://www.npmjs.com/package/lodash)" 'exit=1' 'epoch syntax remains invalid for npm'

# A key's mere presence cannot establish that its release metadata is valid.
for value in null false '"fabricated"' 42 '[]'; do
  jq -nc --argjson value "$value" '{"dist-tags":{"latest":"4.17.21"},versions:{"4.17.21":$value}}' > "$VS_FIXTURE_RESPONSE_FILE"
  out=$(record npm lodash 4.17.21 https://www.npmjs.com/package/lodash)
  assert_contains "$out" 'exit=1' "npm release metadata $value is rejected"
  jq -nc --argjson value "$value" '{info:{version:"2.31.0"},releases:{"2.31.0":[$value]}}' > "$VS_FIXTURE_RESPONSE_FILE"
  out=$(record pip requests 2.31.0 https://pypi.org/project/requests/)
  assert_contains "$out" 'exit=1' "PyPI release file metadata $value is rejected"
done
printf '%s\n' '{"info":{"version":"2.31.0"},"releases":{"2.31.0":[null,{"yanked":true}]}}' > "$VS_FIXTURE_RESPONSE_FILE"
assert_contains "$(record pip requests 2.31.0 https://pypi.org/project/requests/)" 'exit=1' 'malformed and yanked files cannot authorize a release'

# Startup audit must reject malformed latest-version responses, not treat
# their printable JSON representation as a version string.
source "$ROOT/scripts/lib/registries.sh"
for value in null false '""' 42 '[]' '{}'; do
  for eco in npm pip cargo; do
    jq -nc --argjson value "$value" '{"dist-tags":{latest:$value},info:{version:$value},crate:{max_stable_version:$value}}' > "$VS_FIXTURE_RESPONSE_FILE"
    out=$(VS_REQUIRE_ONLINE=1 registry_latest "$eco" example 2>&1; echo "exit=$?")
    assert_contains "$out" 'exit=1' "$eco malformed latest $value fails online audit lookup"
  done
done
printf '%s\n' '{"versions":["13.0.3","14.0.0-preview"]}' > "$VS_FIXTURE_RESPONSE_FILE"
assert_eq 13.0.3 "$(registry_latest csproj Example)" 'NuGet audit and verification use stable latest'
printf '%s\n' '{"versions":["13.0.3",{}]}' > "$VS_FIXTURE_RESPONSE_FILE"
out=$(registry_latest csproj Example 2>&1; echo "exit=$?")
assert_contains "$out" 'exit=1' 'NuGet malformed latest metadata fails audit lookup'
finish_test
