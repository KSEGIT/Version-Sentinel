#!/usr/bin/env bash
VS_TEST_NAME="package-override-compat"
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

class PackageOverrideCompatibility(unittest.TestCase):
    def deps(self, data, intents=False):
        return state.dependencies("package.json", json.dumps(data), intents=intents)

    def fingerprint(self, data):
        return state.dependency_fingerprint("package.json", json.dumps(data))

    def test_pnpm_override_adds_registry_dependency_even_without_direct_entry(self):
        self.assertEqual(self.deps({"pnpm": {"overrides": {"vite": "6.3.5"}}}), [("vite", "6.3.5")])

    def test_version_qualified_npm_overrides_keep_all_replacement_versions(self):
        self.assertEqual(self.deps({"overrides": {"brace-expansion@1": "1.1.13",
            "brace-expansion@2": "2.0.3", "brace-expansion@5": "5.0.5", "@scope/foo@^1": "2.0.0"}}),
            [("@scope/foo", "2.0.0"), ("brace-expansion", "1.1.13"),
             ("brace-expansion", "2.0.3"), ("brace-expansion", "5.0.5")])

    def test_key_selector_and_namespace_survive_intent_normalization(self):
        first = self.deps({"overrides": {"foo@1": "2.0.0"}}, intents=True)
        second = self.deps({"overrides": {"foo@2": "2.0.0"}}, intents=True)
        self.assertEqual(json.loads(first[0][2]), {"location": "overrides.foo@1", "occurrence": 0,
                                                  "selector": {"override": "2.0.0"}})
        self.assertNotEqual(first, second)
        pnpm = self.deps({"pnpm": {"overrides": {"foo": "2.0.0"}}}, intents=True)
        self.assertEqual(json.loads(pnpm[0][2])["location"], "pnpm.overrides.foo")
        self.assertNotEqual(pnpm, self.deps({"overrides": {"foo": "2.0.0"}}, intents=True))

    def test_pnpm_aliases_and_direct_references_keep_real_registry_target(self):
        self.assertEqual(self.deps({"dependencies": {"source": "npm:@scope/real@^1.0.0"},
            "pnpm": {"overrides": {"alias": "npm:other@~2.0.0", "target": "$source"}}}),
            [("@scope/real", "1.0.0"), ("other", "2.0.0")])

    def test_pnpm_reference_uses_optional_then_runtime_then_dev_dependency(self):
        data = {"devDependencies": {"source": "1.0.0"}, "dependencies": {"source": "2.0.0"},
                "optionalDependencies": {"source": "3.0.0"}, "peerDependencies": {"source": "4.0.0"},
                "pnpm": {"overrides": {"target": "$source"}}}
        for section, version in [("optionalDependencies", "3.0.0"),
                                 ("dependencies", "2.0.0"), ("devDependencies", "1.0.0")]:
            with self.subTest(section=section):
                row = next(row for row in self.deps(data, intents=True) if row[0] == "target")
                self.assertEqual(row[:2], ("target", version))
                self.assertEqual(json.loads(row[2])["selector"],
                                 {"override": "$source", "reference": "source", "source": section, "resolved": version})
                del data[section]

    def test_pnpm_peer_only_reference_is_unresolved(self):
        with self.assertRaises(ValueError):
            self.deps({"peerDependencies": {"source": "1.0.0"},
                       "pnpm": {"overrides": {"target": "$source"}}})

    def test_empty_pnpm_reference_does_not_fall_back_to_shadowed_version(self):
        with self.assertRaises(ValueError):
            self.deps({"dependencies": {"source": "1.0.0"}, "optionalDependencies": {"source": ""},
                       "pnpm": {"overrides": {"target": "$source"}}})

    def test_pnpm_fingerprint_tracks_full_override_keys_and_external_values(self):
        before = {"pnpm": {"overrides": {"foo": "^1.0.0", "local": "file:../one"}}}
        for after in [{"pnpm": {"overrides": {"foo": "~1.0.0", "local": "file:../one"}}},
                      {"pnpm": {"overrides": {"foo": "^1.0.0", "local": "file:../two"}}},
                      {"pnpm": {"overrides": {"bar": "^1.0.0", "local": "file:../one"}}}]:
            with self.subTest(after=after):
                self.assertNotEqual(self.fingerprint(before), self.fingerprint(after))
        self.assertEqual(self.fingerprint(before), self.fingerprint(dict(before, name="metadata")))

    def test_unparsed_pnpm_forms_still_fail_closed(self):
        for overrides in [{"foo": {".": "1.0.0"}}, {"parent@1>foo": "1.0.0"},
                          {"foo": "-"}, {"foo": False}, {"foo@": "1.0.0"},
                          {"foo": "$missing"}, {"foo": "npm:"}]:
            with self.subTest(overrides=overrides), self.assertRaises(ValueError):
                self.deps({"pnpm": {"overrides": overrides}})

unittest.main(argv=[sys.argv[0]])
PY
assert_exit_code 0 "$?" 'supported package override extraction and intent regression tests'
VS_TMPDIR=$(mktemp -d)
trap 'rm -rf "$VS_TMPDIR"' EXIT
cd "$VS_TMPDIR" || exit 1
registry_fixture_setup
printf '%s\n' '{"pnpm":{"overrides":{"lodash":"4.17.21"}},"overrides":{"other@1":"4.17.21"}}' > package.json
before=$(file_sha256 package.json) || exit 1
result=$(bash "$SCRIPTS/check-versions.sh" 2>&1); status=$?
assert_exit_code 0 "$status" 'supported override forms complete an online fixture audit'
assert_eq "$before" "$(file_sha256 package.json)" 'override audit leaves manifest unchanged'
content='{"pnpm":{"overrides":{"lodash":"4.17.20"}},"overrides":{"other@1":"4.17.21"}}'
probe() {
  local validator="${1:-validate-detect-manifest-edit.sh}"
  jq -nc --arg path "$VS_TMPDIR/package.json" --arg content "$content" '{tool_name:"Write",tool_input:{file_path:$path,content:$content}}' \
    | bash "$SCRIPTS/$validator" 2>&1
}
result=$(probe); status=$?
assert_exit_code 2 "$status" 'strict pnpm override validation requires online evidence'
result=$(probe detect-manifest-edit.sh); status=$?
assert_exit_code 0 "$status" 'public hook allows an unrecorded pnpm override change'
assert_contains "$result" 'WARNING' 'public hook warns about an unrecorded override'
bash "$SCRIPTS/vs-record.sh" npm lodash 4.17.20 'intentional: override compatibility regression' >/dev/null 2>&1
assert_exit_code 0 "$?" 'override replacement version is verified before recording'
result=$(probe); status=$?
assert_exit_code 0 "$status" 'verified pnpm replacement version passes strict validation'
result=$(probe detect-manifest-edit.sh); status=$?
assert_exit_code 0 "$status" 'public hook allows a verified pnpm override change'
assert_eq '' "$result" 'verified override is silent with security providers disabled'
finish_test
