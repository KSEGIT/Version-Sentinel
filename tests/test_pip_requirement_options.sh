#!/usr/bin/env bash
# Valid global pip options contain no dependencies; appended package specs must not disappear.
VS_TEST_NAME="pip-requirement-options"
TESTS_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPTS="$(cd "$TESTS_DIR/../scripts" && pwd)"
source "$TESTS_DIR/assert.sh"
source "$TESTS_DIR/registry-fixture.sh"
VS_TMPDIR=$(mktemp -d)
trap 'rm -rf "$VS_TMPDIR"' EXIT
cd "$VS_TMPDIR" || exit 1
registry_fixture_setup
for option in \
  '--index-url=https://pypi.org/simple' \
  '--index-url https://pypi.org/simple' \
  '--extra-index-url=https://packages.example.invalid/simple' \
  '-i https://pypi.org/simple' \
  '-ihttps://pypi.org/simple' \
  '-f ./wheels' \
  '--find-links=./wheels' \
  '--require-hashes' \
  '--no-require-hashes' \
  '--only-binary=:all:' \
  '--no-binary :none:' \
  '--prefer-binary --pre --no-index' \
  '--trusted-host=packages.example.invalid --find-links "./wheel directory"' \
  '--use-feature=fast-deps' \
  '-e .' \
  '--editable=./local' \
  '--editable="./local directory"' \
  '-e C:\local-project'; do
  printf '%s\n' "$option" 'requests==2.31.0' > requirements.txt
  result=$(bash "$SCRIPTS/audit-state.sh" deps requirements.txt 2>&1); status=$?
  assert_exit_code 0 "$status" "valid pip option: $option"
  assert_eq $'requests\t2.31.0' "$result" "option cannot remove registry dependency: $option"
done
for option in \
  '--index-url=https://pypi.org/simple requests==2.31.0' \
  '--index-url https://pypi.org/simple requests==2.31.0' \
  '--require-hashes requests==2.31.0' \
  '--pre requests==2.31.0' \
  '--find-links ./wheels --unknown-flag' \
  '--unknown-flag=true' \
  '--only-binary' \
  '--no-index=unexpected' \
  '--index-url --pre'; do
  printf '%s\n' "$option" | bash "$SCRIPTS/audit-state.sh" validate-content requirements.txt >/dev/null 2>&1
  assert_exit_code 2 "$?" "ambiguous/unparsed pip option content blocks: $option"
done
# Keep the audit bound to included files and use canonical verification even with custom indexes.
printf '%s\n' '--index-url=https://packages.example.invalid/simple' '--require-hashes' '-r requirements-base.txt' > requirements.txt
printf '%s\n' 'requests==2.31.0' > requirements-base.txt
result=$(bash "$SCRIPTS/check-versions.sh" 2>&1); status=$?
assert_exit_code 0 "$status" 'custom index option does not break online audit'
assert_contains "$result" 'requests' 'include dependency remains in audit'
bash "$SCRIPTS/audit-state.sh" covers "$PWD" requirements-base.txt >/dev/null 2>&1
assert_exit_code 0 "$?" 'include inventory still enforced with option lines'
bash "$SCRIPTS/vs-record.sh" pip requests 2.31.0 https://pypi.org/project/requests/ >/dev/null 2>&1
assert_exit_code 0 "$?" 'canonical registry check succeeds independently of custom index option'
VS_FIXTURE_NETWORK_FAIL=1 bash "$SCRIPTS/check-versions.sh" >/dev/null 2>&1
assert_exit_code 2 "$?" 'custom index cannot turn failed canonical online audit into success'
finish_test
