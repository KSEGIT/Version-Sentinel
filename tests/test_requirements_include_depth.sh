#!/usr/bin/env bash
# Explicit requirements/constraints remain audited beyond bounded discovery.
VS_TEST_NAME="requirements-include-depth"
TESTS_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$TESTS_DIR/.." && pwd)"
source "$TESTS_DIR/assert.sh"
source "$TESTS_DIR/registry-fixture.sh"
VS_TMPDIR=$(mktemp -d)
trap 'rm -rf "$VS_TMPDIR"' EXIT
registry_fixture_setup
mkdir -p "$VS_TMPDIR/project/one/two/three/requirements/deeper"
cd "$VS_TMPDIR/project" || exit 1
entry=one/two/three/requirements.txt
included=one/two/three/requirements/requirements-base.txt
constraint=one/two/three/requirements/deeper/constraints-lock.txt
printf '%s\n' '-r requirements/requirements-base.txt' > "$entry"
printf '%s\n' 'requests==2.31.0' '-c deeper/constraints-lock.txt' > "$included"
printf '%s\n' 'flask==3.0.0' > "$constraint"
result=$(bash "$ROOT/scripts/check-versions.sh" 2>&1); status=$?
assert_exit_code 0 "$status" "depth-four manifest audits its deeper include closure: $result"
if [[ "$status" -ne 0 ]]; then finish_test; exit "$?"; fi
assert_contains "$result" 'requests' 'included dependency is checked against registry'
assert_contains "$result" 'flask' 'transitive constraint dependency is checked against registry'
for manifest in "$entry" "$included" "$constraint"; do
  bash "$ROOT/scripts/audit-state.sh" covers "$PWD" "$manifest" >/dev/null 2>&1
  assert_exit_code 0 "$?" "explicit include closure is covered: $manifest"
done

# A deeper file without an explicit reference must not broaden discovery.
unreferenced=one/two/three/requirements/requirements-unreferenced.txt
printf '%s\n' 'requests==2.30.0' > "$unreferenced"
bash "$ROOT/scripts/audit-state.sh" gate "$PWD" >/dev/null 2>&1
assert_exit_code 0 "$?" 'unreferenced deeper file does not change bounded inventory'
bash "$ROOT/scripts/audit-state.sh" covers "$PWD" "$unreferenced" >/dev/null 2>&1
assert_exit_code 2 "$?" 'unreferenced deeper manifest cannot authorize explicit inputs'
unreferenced_missing=one/two/three/requirements/requirements-unreferenced-missing.txt
result=$(bash "$ROOT/scripts/recover-manifest.sh" approve "$unreferenced_missing" --user-confirmed 'Synthetic fixture consent, not a real project manifest' 2>&1); status=$?
assert_exit_code 2 "$status" 'recovery cannot register an unreferenced deeper manifest'
assert_contains "$result" 'not a required requirements include' 'recovery explains the missing include authority'

# Hashes of both direct includes and transitive constraints protect the gate.
printf '%s\n' 'requests==2.30.0' '-c deeper/constraints-lock.txt' > "$included"
bash "$ROOT/scripts/audit-state.sh" gate "$PWD" >/dev/null 2>&1
assert_exit_code 2 "$?" 'changing depth-five include invalidates completed evidence'
bash "$ROOT/scripts/check-versions.sh" >/dev/null 2>&1
assert_exit_code 0 "$?" 'changed direct include can be re-audited'
printf '%s\n' 'flask==2.0.0' > "$constraint"
bash "$ROOT/scripts/audit-state.sh" gate "$PWD" >/dev/null 2>&1
assert_exit_code 2 "$?" 'changing depth-six constraint invalidates completed evidence'
bash "$ROOT/scripts/check-versions.sh" >/dev/null 2>&1
assert_exit_code 0 "$?" 'changed transitive constraint can be re-audited'
VS_FIXTURE_NETWORK_FAIL=1 bash "$ROOT/scripts/check-versions.sh" >/dev/null 2>&1
assert_exit_code 2 "$?" 'deeper include coverage still requires successful registry checks'
bash "$ROOT/scripts/audit-state.sh" gate "$PWD" >/dev/null 2>&1
assert_exit_code 2 "$?" 'failed deeper audit revokes prior successful evidence'
bash "$ROOT/scripts/check-versions.sh" >/dev/null 2>&1
assert_exit_code 0 "$?" 'registry recovery permits a fresh audit'

# Required deeper inputs retain the existing exact-path recovery-consent flow.
rm "$constraint"
result=$(bash "$ROOT/scripts/check-versions.sh" 2>&1); status=$?
assert_exit_code 2 "$status" 'deleted deeper constraint blocks audit'
assert_contains "$result" 'constraints-lock.txt' 'missing deeper constraint is identified'
bash "$ROOT/scripts/audit-state.sh" recovery-allowed "$PWD" "$constraint" >/dev/null 2>&1
assert_exit_code 2 "$?" 'deeper missing include cannot be restored without consent'
bash "$ROOT/scripts/recover-manifest.sh" approve "$constraint" --user-confirmed 'Synthetic fixture consent to restore the exact required constraint' >/dev/null 2>&1
assert_exit_code 0 "$?" 'consent may cover an exact required deeper include'
[[ ! -e "$constraint" ]] || _fail 'recovery approval must not recreate the deeper file'
bash "$ROOT/scripts/audit-state.sh" recovery-allowed "$PWD" "$constraint" >/dev/null 2>&1
assert_exit_code 0 "$?" 'approved deeper missing path can be recovered'
printf '%s\n' 'flask==3.0.0' > "$constraint"
bash "$ROOT/scripts/check-versions.sh" >/dev/null 2>&1
assert_exit_code 0 "$?" 'deeper recovery still needs a successful fresh audit'

# Canonical project boundaries, excluded trees, and symlink escapes stay closed.
mkdir -p "$VS_TMPDIR/outside" "$VS_TMPDIR/escape-project/one/two/three/requirements"
printf '%s\n' 'requests==2.31.0' > "$VS_TMPDIR/outside/requirements-other.txt"
cd "$VS_TMPDIR/escape-project" || exit 1
printf '%s\n' '-r ../../../../outside/requirements-other.txt' > one/two/three/requirements.txt
result=$(bash "$ROOT/scripts/check-versions.sh" 2>&1); status=$?
assert_exit_code 2 "$status" 'deeper include cannot escape the project root'
assert_contains "$result" 'outside project' 'canonical outside-project boundary remains enforced'
python3 - "$VS_TMPDIR/outside/requirements-other.txt" <<'PY'
import os, pathlib, sys
path = pathlib.Path('one/two/three/requirements/requirements-link.txt')
os.symlink(sys.argv[1], path)
assert path.is_symlink()
PY
assert_exit_code 0 "$?" 'outside-project symlink fixture is an actual symlink'
printf '%s\n' '-r requirements/requirements-link.txt' > one/two/three/requirements.txt
result=$(bash "$ROOT/scripts/check-versions.sh" 2>&1); status=$?
assert_exit_code 2 "$status" 'deeper symlink include cannot escape the project root'
assert_contains "$result" 'outside project' 'symlink resolution still enforces canonical root'
mkdir -p one/two/three/node_modules
printf '%s\n' 'requests==2.31.0' > one/two/three/node_modules/requirements-vendor.txt
printf '%s\n' '-r node_modules/requirements-vendor.txt' > one/two/three/requirements.txt
result=$(bash "$ROOT/scripts/check-versions.sh" 2>&1); status=$?
assert_exit_code 2 "$status" 'explicit deeper includes cannot enter excluded vendor trees'
assert_contains "$result" 'outside supported audit scope' 'excluded directory policy remains enforced'
printf '%s\n' '[dependencies]' 'serde = "1.0.196"' > one/two/three/requirements/Cargo.toml
printf '%s\n' '-r requirements/Cargo.toml' > one/two/three/requirements.txt
result=$(bash "$ROOT/scripts/check-versions.sh" 2>&1); status=$?
assert_exit_code 2 "$status" 'requirements include cannot extend discovery to another ecosystem'
assert_contains "$result" 'unsupported requirements include name' 'only supported pip include filenames extend the closure'
finish_test
