#!/usr/bin/env bash
# PEP 508 accepts one optional parenthesized version-specifier list.
VS_TEST_NAME="python-parenthesized-specifiers"
TESTS_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$TESTS_DIR/.." && pwd)"
source "$TESTS_DIR/assert.sh"
source "$TESTS_DIR/registry-fixture.sh"
VS_TMPDIR=$(mktemp -d)
trap 'rm -rf "$VS_TMPDIR"' EXIT
registry_fixture_setup
cd "$VS_TMPDIR" || exit 1

# Rejecting valid outer parentheses must not suppress a declared dependency.
printf '%s\n' '[project]' 'dependencies = ["numpy (>=1.26.4,<3.0.0)"]' > pyproject.toml
result=$(bash "$ROOT/scripts/audit-state.sh" deps pyproject.toml 2>&1); status=$?
assert_exit_code 0 "$status" "valid NumPy selector is accepted: $result"
assert_eq $'numpy\t1.26.4' "$result" 'existing first-bound audit policy applies inside parentheses'

printf '%s\n' 'requests[security] ( == 2.31.0 ) ; python_version >= "3.11"' 'flask (~=3.0.0)' > requirements.txt
result=$(bash "$ROOT/scripts/audit-state.sh" deps requirements.txt 2>&1); status=$?
assert_exit_code 0 "$status" "requirements accepts extras, markers and inner whitespace: $result"
assert_eq $'flask\t3.0.0\nrequests\t2.31.0' "$result" 'all parenthesized requirements remain in audit'
printf '%s\n' 'requests (==2.*)' > requirements.txt
result=$(bash "$ROOT/scripts/audit-state.sh" deps requirements.txt 2>&1); status=$?
assert_exit_code 0 "$status" 'wildcard parentheses retain the floating-selector policy'
assert_eq $'requests\t__version_sentinel_unpinned__' "$result" 'parentheses cannot turn wildcard into an exact version'

for spec in 'requests ()' 'requests ( )' 'requests ((==2.31.0))' 'requests (==2.31.0' \
            'requests ==2.31.0)' 'requests (==2.31.0) suffix' 'requests (>=2.0,,<3.0)' \
            'requests (git+https://example.invalid/repo)' 'requests (==2.31.0) (==2.30.0)'; do
  printf '%s\n' "$spec" | bash "$ROOT/scripts/audit-state.sh" validate-content requirements.txt >/dev/null 2>&1
  assert_exit_code 2 "$?" "malformed or unsupported parenthesized selector fails closed: $spec"
done

# A completed online audit still covers the full raw selector and every file.
printf '%s\n' '[project]' 'dependencies = ["requests (>=2.30.0,<3.0.0)"]' > pyproject.toml
printf '%s\n' 'flask (==3.0.0)' > requirements.txt
result=$(bash "$ROOT/scripts/check-versions.sh" 2>&1); status=$?
assert_exit_code 0 "$status" "parenthesized selectors complete registry-backed audit: $result"
assert_contains "$result" 'requests' 'range dependency is checked against upstream'
assert_contains "$result" 'flask' 'exact dependency is checked against upstream'
bash "$ROOT/scripts/audit-state.sh" gate "$PWD" >/dev/null 2>&1
assert_exit_code 0 "$?" 'successful parenthesized audit authorizes unchanged project'
printf '%s\n' '[project]' 'dependencies = ["requests (>=2.30.0,<4.0.0)"]' > pyproject.toml
bash "$ROOT/scripts/audit-state.sh" gate "$PWD" >/dev/null 2>&1
assert_exit_code 2 "$?" 'upper-bound change invalidates audit despite unchanged selected first bound'
bash "$ROOT/scripts/check-versions.sh" >/dev/null 2>&1
assert_exit_code 0 "$?" 'changed valid selector requires and permits a fresh audit'
VS_FIXTURE_NETWORK_FAIL=1 bash "$ROOT/scripts/check-versions.sh" >/dev/null 2>&1
assert_exit_code 2 "$?" 'parentheses never bypass an upstream lookup failure'
bash "$ROOT/scripts/audit-state.sh" gate "$PWD" >/dev/null 2>&1
assert_exit_code 2 "$?" 'failed online audit revokes previous evidence'

finish_test
