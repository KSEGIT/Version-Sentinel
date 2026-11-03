#!/usr/bin/env bash
# Unparsed resolver overrides must never be mistaken for dependency-free metadata.
VS_TEST_NAME="unsupported-dependency-selectors"
TESTS_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPTS="$(cd "$TESTS_DIR/../scripts" && pwd)"
source "$TESTS_DIR/assert.sh"
source "$TESTS_DIR/registry-fixture.sh"
VS_TMPDIR=$(mktemp -d)
trap 'rm -rf "$VS_TMPDIR"' EXIT
cd "$VS_TMPDIR" || exit 1
registry_fixture_setup
printf '%s\n' '{"name":"demo","dependencies":{}}' > package.json
printf '%s\n' '[package]' 'name="demo"' 'version="0.1.0"' > Cargo.toml
bash "$SCRIPTS/check-versions.sh" >/dev/null 2>&1
probe() {
  jq -nc --arg path "$1" --arg content "$2" '{tool_name:"Write",tool_input:{file_path:$path,content:$content}}' \
    | bash "$SCRIPTS/detect-manifest-edit.sh" 2>&1
}
for content in \
  '{"dependencies":{},"overrides":{"body-parser":"99.99.99"}}' \
  '{"dependencies":{},"resolutions":{"body-parser":"99.99.99"}}' \
  '{"dependencies":{},"pnpm":{"overrides":{"body-parser":"99.99.99"}}}' \
  '{"dependencies":{},"catalog":{"body-parser":"99.99.99"}}' \
  '{"dependencies":{},"catalogs":{"default":{"body-parser":"99.99.99"}}}' \
  '{"dependencies":{},"pnpm":{"packageExtensions":{"express@*":{"dependencies":{"body-parser":"99.99.99"}}}}}'; do
  result=$(probe package.json "$content"); status=$?
  assert_exit_code 2 "$status" 'unsupported npm resolver dependency mutation blocks'
  assert_contains "$result" 'Unsupported dependency-selector' 'npm resolver limitation is actionable'
  printf '%s' "$content" | bash "$SCRIPTS/audit-state.sh" validate-content package.json >/dev/null 2>&1
  assert_exit_code 2 "$?" 'unsupported npm resolver cannot validate as metadata'
done
result=$(probe package.json '{"name":"renamed","dependencies":{},"overrides":{},"resolutions":{},"pnpm":{"overrides":{}}}'); status=$?
assert_exit_code 0 "$status" 'empty override maps do not block ordinary metadata'
for section in patch replace; do
  if [[ "$section" == patch ]]; then
    content=$'[package]\nname="demo"\nversion="0.1.0"\n[patch.crates-io]\nserde={version="99.99.99"}\n'
  else
    content=$'[package]\nname="demo"\nversion="0.1.0"\n[replace]\n"serde:1.0.196"={version="99.99.99"}\n'
  fi
  result=$(probe Cargo.toml "$content"); status=$?
  assert_exit_code 2 "$status" 'unsupported Cargo resolution override blocks'
  assert_contains "$result" 'Unsupported dependency-selector' 'Cargo resolver limitation is actionable'
done
printf '%s\n' '[dependencies]' 'serde="1.0.196"' '[patch]' '[replace]' | bash "$SCRIPTS/audit-state.sh" validate-content Cargo.toml >/dev/null 2>&1
assert_exit_code 0 "$?" 'empty Cargo resolver maps retain compatibility'
# A pre-existing unsupported override must fail the startup audit as well.
printf '%s\n' '{"overrides":{"body-parser":"99.99.99"}}' > package.json
result=$(bash "$SCRIPTS/check-versions.sh" 2>&1); status=$?
assert_exit_code 2 "$status" 'startup audit rejects unsupported npm dependency selectors'
assert_contains "$result" 'Unsupported dependency-selector' 'startup identifies unsupported resolver'
finish_test
