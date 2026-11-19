#!/usr/bin/env bash
VS_TEST_NAME="poetry-multiple-constraints"
TESTS_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPTS="$(cd "$TESTS_DIR/../scripts" && pwd)"
source "$TESTS_DIR/assert.sh"
python3 - "$SCRIPTS/lib" <<'PY'
import importlib.util
import json
import sys
import unittest

sys.path.insert(0, sys.argv[1])
spec = importlib.util.spec_from_file_location("project_state", sys.argv[1] + "/project-state.py")
state = importlib.util.module_from_spec(spec)
spec.loader.exec_module(state)

PLATFORM_DEPENDENCIES = """[tool.poetry.dependencies]
torch = [
    {version = "2.2.1", platform = "darwin", markers = "sys_platform == 'darwin'", source = "pypi"},
    {version = "2.2.1+cpu", platform = "linux", markers = "sys_platform == 'linux'", source = "pytorch-cpu"},
    {version = "2.2.1+cpu", platform = "win32", markers = "sys_platform == 'win32'", source = "pytorch-windows", python = ">=3.10", extras = ["opt-einsum"], optional = true},
]
"""

class PoetryMultipleConstraints(unittest.TestCase):
    def deps(self, content, intents=False):
        return state.dependencies("pyproject.toml", content, intents=intents)

    def test_all_platform_versions_are_audited_and_cpu_version_is_exact(self):
        self.assertEqual(self.deps(PLATFORM_DEPENDENCIES),
                         [("torch", "2.2.1"), ("torch", "2.2.1+cpu")])

    def test_same_version_entries_keep_complete_selector_and_occurrence(self):
        rows = self.deps(PLATFORM_DEPENDENCIES, intents=True)
        self.assertEqual([(pkg, version, json.loads(intent)) for pkg, version, intent in rows], [
            ("torch", "2.2.1", {"location": "tool.poetry.dependencies.torch", "occurrence": 0,
                "selector": {"version": "2.2.1", "platform": "darwin", "markers": "sys_platform == 'darwin'", "source": "pypi"}}),
            ("torch", "2.2.1+cpu", {"location": "tool.poetry.dependencies.torch", "occurrence": 1,
                "selector": {"version": "2.2.1+cpu", "platform": "linux", "markers": "sys_platform == 'linux'", "source": "pytorch-cpu"}}),
            ("torch", "2.2.1+cpu", {"location": "tool.poetry.dependencies.torch", "occurrence": 2,
                "selector": {"version": "2.2.1+cpu", "platform": "win32", "markers": "sys_platform == 'win32'", "source": "pytorch-windows", "python": ">=3.10", "extras": ["opt-einsum"], "optional": True}}),
        ])

    def test_marker_and_source_only_changes_affect_intent_and_fingerprint(self):
        before = self.deps(PLATFORM_DEPENDENCIES, intents=True)
        fingerprint = state.dependency_fingerprint("pyproject.toml", PLATFORM_DEPENDENCIES)
        for old, new in [("sys_platform == 'linux'", "sys_platform != 'darwin'"),
                         ('source = "pytorch-cpu"', 'source = "other-cpu"')]:
            with self.subTest(new=new):
                changed = PLATFORM_DEPENDENCIES.replace(old, new)
                self.assertNotEqual(before, self.deps(changed, intents=True))
                self.assertNotEqual(fingerprint, state.dependency_fingerprint("pyproject.toml", changed))

    def test_identical_entries_retain_separate_occurrences(self):
        content = '[tool.poetry.dependencies]\nfoo = [{version = "1.0.0"}, {version = "1.0.0"}]'
        self.assertEqual(self.deps(content), [("foo", "1.0.0")])
        self.assertEqual([json.loads(row[2])["occurrence"] for row in self.deps(content, intents=True)], [0, 1])

    def test_lists_work_in_legacy_dev_and_named_group_sections(self):
        content = """[tool.poetry.dev-dependencies]
pytest = [{version = "7.4.0", python = "<3.12"}, {version = "8.0.0", python = ">=3.12"}]
[tool.poetry.group.docs.dependencies]
sphinx = [{version = "7.0.0", python = "<3.12"}, {version = "8.0.0", python = ">=3.12"}]
"""
        self.assertEqual(self.deps(content), [("pytest", "7.4.0"), ("pytest", "8.0.0"),
                                              ("sphinx", "7.0.0"), ("sphinx", "8.0.0")])
        self.assertEqual({json.loads(row[2])["location"] for row in self.deps(content, intents=True)},
                         {"tool.poetry.dev-dependencies.pytest", "tool.poetry.group.docs.dependencies.sphinx"})

    def test_string_table_and_external_source_behavior_is_preserved(self):
        content = """[tool.poetry.dependencies]
python = ">=3.10"
requests = "^2.31.0"
click = {version = "8.1.7", optional = true}
local = {path = "../local"}
foo = [{url = "https://example.com/foo.whl", platform = "darwin"}, {version = "1.0.0", platform = "linux"}]
bar = [{path = "../bar"}, {git = "https://example.com/bar.git"}]
unpinned = [{optional = true}]
[tool.poetry.dev-dependencies]
pytest = "8.0.0"
[tool.poetry.group.docs.dependencies]
sphinx = {version = "7.0.0"}
"""
        self.assertEqual(self.deps(content), [("click", "8.1.7"), ("foo", "1.0.0"),
            ("pytest", "8.0.0"), ("requests", "2.31.0"), ("sphinx", "7.0.0"), ("unpinned", state.UNPINNED)])

    def test_empty_and_malformed_lists_fail_closed(self):
        for raw in ['[]', '["1.0.0"]', '[false]', '[1]', '[[{version = "1.0.0"}]]',
                    '[{version = "1.0.0"}, "2.0.0"]', '[{version = false}]', '[{version = ["1.0.0"]}]']:
            with self.subTest(raw=raw), self.assertRaises(ValueError):
                self.deps('[tool.poetry.dependencies]\nfoo = ' + raw)

unittest.main(argv=[sys.argv[0]])
PY
assert_exit_code 0 "$?" 'Poetry multiple-constraint extraction, intent, and validation'
finish_test
