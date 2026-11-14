#!/usr/bin/env bash
# Flat overrides use the same strict audit and change gate as direct dependencies.
VS_TEST_NAME="npm-overrides"
TESTS_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPTS="$(cd "$TESTS_DIR/../scripts" && pwd)"
source "$TESTS_DIR/assert.sh"
source "$TESTS_DIR/registry-fixture.sh"
python3 - "$SCRIPTS/lib" <<'PY'
import importlib.util
import json
import sys
import unittest
sys.path.insert(0, sys.argv[1])
spec = importlib.util.spec_from_file_location("project_state", sys.argv[1] + "/project-state.py")
state = importlib.util.module_from_spec(spec)
spec.loader.exec_module(state)

class Overrides(unittest.TestCase):
    def deps(self, data, intents=False):
        return state.dependencies("package.json", json.dumps(data), intents=intents)

    def test_flat_and_direct_reference(self):
        self.assertEqual(self.deps({"dependencies": {"postcss": "^8.5.6"},
                                   "overrides": {"postcss": "$postcss", "sharp": "^0.35.4"}}),
                         [("postcss", "8.5.6"), ("sharp", "0.35.4")])

    def test_scoped_alias_and_cross_package_reference(self):
        self.assertEqual(self.deps({"dependencies": {"@scope/source": "npm:real@^1.0.0"},
                                   "overrides": {"@scope/target": "$@scope/source", "alias": "npm:@scope/real@~2.0.0"}}),
                         [("@scope/real", "2.0.0"), ("real", "1.0.0")])

    def test_reference_precedence_matches_npm(self):
        data = {section: {"foo": value} for section, value in [
            ("devDependencies", "1.0.0"), ("optionalDependencies", "2.0.0"),
            ("dependencies", "3.0.0"), ("peerDependencies", "4.0.0")]}
        data["overrides"] = {"bar": "$foo"}
        for section, value in [("devDependencies", "1.0.0"), ("optionalDependencies", "2.0.0"),
                               ("dependencies", "3.0.0"), ("peerDependencies", "4.0.0")]:
            self.assertIn(("bar", value), self.deps(data))
            del data[section]

    def test_unpinned_overrides_are_visible(self):
        for value in ["latest", "*", "1.x", "1.0.0 || 2.0.0"]:
            self.assertEqual(self.deps({"overrides": {"foo": value}}), [("foo", state.UNPINNED)])

    def test_unsupported_shapes_fail_closed(self):
        for overrides in [{"foo": {".": "1.0.0"}}, {"foo@^1": "2.0.0"},
                          {"foo": False}, {"foo": "$missing"}, {"foo": "$"},
                          {"bad/name": "1.0.0"}, {"foo bar": "1.0.0"}, {"foo": "npm:"}]:
            with self.subTest(overrides=overrides), self.assertRaises(ValueError):
                self.deps({"overrides": overrides})

    def test_selector_and_resolved_reference_changes_remain_visible(self):
        data = {"dependencies": {"foo": "^1.0.0", "bar": "^1.0.0"}, "overrides": {"target": "$foo"}}
        before = next(row for row in self.deps(data, intents=True) if row[0] == "target")
        data["overrides"]["target"] = "$bar"
        self.assertNotEqual(before, next(row for row in self.deps(data, intents=True) if row[0] == "target"))
        data["overrides"]["target"] = "$foo"
        data["dependencies"]["foo"] = "~1.0.0"
        self.assertNotEqual(before, next(row for row in self.deps(data, intents=True) if row[0] == "target"))

    def test_override_fingerprint_tracks_registry_and_external_changes(self):
        for first, second in [("^1.0.0", "~1.0.0"), ("file:../one", "file:../two")]:
            before = state.dependency_fingerprint("package.json", json.dumps({"overrides": {"foo": first}}))
            after = state.dependency_fingerprint("package.json", json.dumps({"overrides": {"foo": second}}))
            self.assertNotEqual(before, after)

unittest.main(argv=[sys.argv[0]])
PY
assert_exit_code 0 "$?" 'strict override extraction, intent, and fingerprint regression tests'
VS_TMPDIR=$(mktemp -d)
trap 'rm -rf "$VS_TMPDIR"' EXIT
cd "$VS_TMPDIR" || exit 1
registry_fixture_setup
printf '%s\n' '{"dependencies":{"lodash":"4.17.21"},"overrides":{"lodash":"$lodash","other":"4.17.21"}}' > package.json
before=$(shasum package.json)
result=$(bash "$SCRIPTS/check-versions.sh" 2>&1); status=$?
assert_exit_code 0 "$status" 'existing flat overrides audit automatically'
assert_eq "$before" "$(shasum package.json)" 'automatic handling preserves the manifest'
probe() {
  jq -nc --arg path "$VS_TMPDIR/package.json" --arg content "$1" '{tool_name:"Write",tool_input:{file_path:$path,content:$content}}' \
    | bash "$SCRIPTS/detect-manifest-edit.sh" 2>&1
}
content='{"dependencies":{"lodash":"4.17.21"},"overrides":{"lodash":"$lodash","other":"4.17.20"}}'
result=$(probe "$content"); status=$?
assert_exit_code 2 "$status" 'override mutation cannot bypass the online record gate'
bash "$SCRIPTS/vs-record.sh" npm other 4.17.20 'intentional: compatibility regression test' >/dev/null 2>&1
assert_exit_code 0 "$?" 'override pin is verified online before recording'
result=$(probe "$content"); status=$?
assert_exit_code 0 "$status" 'online-verified override mutation passes'
printf '%s\n' '{"overrides":{"other":"99.99.99"}}' > package.json
result=$(bash "$SCRIPTS/check-versions.sh" 2>&1); status=$?
assert_exit_code 0 "$status" 'override drift has the same startup policy as direct dependencies'
assert_contains "$result" 'DRIFT' 'override version drift is reported'
bash "$SCRIPTS/vs-record.sh" npm other 99.99.99 'intentional: nonexistent version test' >/dev/null 2>&1
assert_exit_code 1 "$?" 'nonexistent override versions cannot be recorded online'
printf '%s\n' '{"overrides":{"other":{".":"4.17.21"}}}' > package.json
result=$(bash "$SCRIPTS/check-versions.sh" 2>&1); status=$?
assert_exit_code 2 "$status" 'unsupported shapes remain blocked'
assert_contains "$result" 'Unsupported dependency-selector' 'unsupported shapes identify the parser limitation'
[[ "$result" != *'Ask Daniel'* ]] || _fail 'valid unsupported selectors must not request manifest repair'
result=$(probe '{"name":"metadata","overrides":{"other":{".":"4.17.21"}}}'); status=$?
assert_exit_code 2 "$status" 'unsupported existing selectors cannot be edited without full parser tracking'
[[ "$result" != *'Ask Daniel'* ]] || _fail 'edit gate must not request consent to repair supported JSON with unsupported selectors'
finish_test
