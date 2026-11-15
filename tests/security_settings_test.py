"""Saved provider settings cross the hook/standalone CLI boundary safely."""
import importlib.util
import json
import os
from pathlib import Path
import shlex
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

LIB = Path(__file__).resolve().parents[1] / 'scripts/lib'


def load_resolver():
    path = LIB / 'security-settings.py'
    assert path.is_file(), 'saved security settings resolver is missing'
    spec = importlib.util.spec_from_file_location('security_settings', path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class SavedSettingsTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name).resolve()

    def resolver(self, listing=None, configured=None):
        module = load_resolver()
        listing = listing if listing is not None else [
            {'id': 'version-sentinel@fixture', 'installPath': str(self.root)}]
        configured = configured if configured is not None else {
            'inputs': {'security_osv': 'false', 'security_npm_audit': 'true'},
            'configured': ['security_osv', 'security_npm_audit'], 'unconfigured': []}
        process = patch.object(module.subprocess, 'run', side_effect=[
            subprocess.CompletedProcess([], 0, json.dumps(listing), ''),
            subprocess.CompletedProcess([], 0, json.dumps(configured), '')])
        executable = patch.object(module.shutil, 'which', return_value='/fixture/claude')
        self.addCleanup(process.stop)
        self.addCleanup(executable.stop)
        self.process = process.start()
        executable.start()
        return module

    def test_saved_false_is_loaded_for_standalone_audit(self):
        module = self.resolver()
        result = module.saved_overrides(self.root, {})
        self.assertEqual(result, {'VS_SECURITY_OSV': 'false', 'VS_SECURITY_NPM_AUDIT': 'true'})
        self.assertEqual(self.process.call_args_list[0].args[0][1:], ['plugin', 'list', '--json'])
        self.assertEqual(self.process.call_args_list[1].args[0][1:],
                         ['plugin', 'configure', 'version-sentinel@fixture', '--json'])
        for call in self.process.call_args_list:
            self.assertIs(call.kwargs['stdin'], subprocess.DEVNULL)
            self.assertLessEqual(call.kwargs['timeout'], 10)

    def test_explicit_hook_and_shell_values_take_precedence(self):
        module = self.resolver()
        values = {'VS_SECURITY_OSV': 'true', 'CLAUDE_PLUGIN_OPTION_SECURITY_NPM_AUDIT': 'false'}
        self.assertEqual(module.saved_overrides(self.root, values), {})
        self.process.assert_not_called()

    def test_only_absent_option_is_filled(self):
        module = self.resolver()
        self.assertEqual(module.saved_overrides(self.root, {'VS_SECURITY_OSV': 'true'}),
                         {'VS_SECURITY_NPM_AUDIT': 'true'})

    def test_no_cli_or_no_matching_install_keeps_default_on(self):
        module = self.resolver(listing=[{'id': 'version-sentinel@other', 'installPath': str(self.root / 'other')}])
        self.assertEqual(module.saved_overrides(self.root, {}), {})
        self.assertEqual(self.process.call_count, 1)
        with patch.object(module.shutil, 'which', return_value=None):
            self.assertEqual(module.saved_overrides(self.root, {}), {})

    def test_in_place_install_uses_documented_read_from_folder(self):
        module = self.resolver(listing=[{'id': 'version-sentinel@fixture',
                                       'installPath': str(self.root / 'cache'),
                                       'readFromFolder': str(self.root)}])
        self.assertEqual(module.saved_overrides(self.root, {})['VS_SECURITY_OSV'], 'false')

    def test_ambiguous_matching_install_blocks(self):
        module = self.resolver(listing=[{'id': 'version-sentinel@one', 'installPath': str(self.root)},
                                       {'id': 'version-sentinel@two', 'installPath': str(self.root)}])
        with self.assertRaisesRegex(ValueError, 'ambiguous'):
            module.saved_overrides(self.root, {})

    def test_relative_or_empty_install_path_cannot_silently_use_defaults(self):
        for location in ('', 'relative-install'):
            module = self.resolver(listing=[{'id': 'version-sentinel@fixture', 'installPath': location}])
            with self.assertRaisesRegex(ValueError, 'installation path'):
                module.saved_overrides(self.root, {})

    def test_failed_or_unsupported_host_lookup_blocks_without_values(self):
        module = self.resolver()
        self.process.side_effect = [subprocess.CompletedProcess([], 1, '', 'private fixture text')]
        with self.assertRaisesRegex(ValueError, 'Cannot resolve') as raised:
            module.saved_overrides(self.root, {})
        self.assertNotIn('private fixture text', str(raised.exception))

    def test_matching_install_configuration_failure_blocks(self):
        module = self.resolver()
        self.process.side_effect = [
            subprocess.CompletedProcess([], 0, json.dumps([{'id': 'version-sentinel@fixture',
                                                          'installPath': str(self.root)}]), ''),
            subprocess.CompletedProcess([], 1, '', 'private fixture text')]
        with self.assertRaisesRegex(ValueError, 'Cannot resolve'):
            module.saved_overrides(self.root, {})

    def test_unset_saved_option_keeps_true_default(self):
        module = self.resolver(configured={'inputs': {}, 'configured': [],
                                          'unconfigured': ['security_osv', 'security_npm_audit']})
        self.assertEqual(module.saved_overrides(self.root, {}), {})

    def test_saved_window_is_honored_during_provider_lookup(self):
        module = self.resolver(configured={
            'inputs': {'security_osv': 'false', 'security_npm_audit': 'false', 'window_hours': '8'},
            'configured': ['security_osv', 'security_npm_audit', 'window_hours']})
        result = module.saved_overrides(self.root, {})
        self.assertEqual(result['VS_SECURITY_OSV'], 'false')
        self.assertEqual(result['VS_SECURITY_NPM_AUDIT'], 'false')
        self.assertIn('VS_WINDOW_HOURS', result)
        self.assertEqual(float(result['VS_WINDOW_HOURS']), 8)

    def test_explicit_window_wins_and_window_alone_does_not_trigger_lookup(self):
        for key in ('VS_WINDOW_HOURS', 'CLAUDE_PLUGIN_OPTION_WINDOW_HOURS'):
            module = self.resolver(configured={'inputs': {'security_osv': 'false', 'window_hours': 'bad'},
                                              'configured': ['security_osv', 'window_hours']})
            result = module.saved_overrides(self.root, {key: '48'})
            self.assertNotIn('VS_WINDOW_HOURS', result)
        module = self.resolver()
        self.assertEqual(module.saved_overrides(self.root, {'VS_SECURITY_OSV': 'true',
                                                           'VS_SECURITY_NPM_AUDIT': 'false'}), {})
        self.process.assert_not_called()

    def test_invalid_saved_window_blocks_without_exposing_value(self):
        for value in ('private invalid text', 'nan', 'inf', '0', '169', True):
            module = self.resolver(configured={'inputs': {'security_osv': 'false', 'window_hours': value},
                                              'configured': ['security_osv', 'window_hours']})
            with self.assertRaisesRegex(ValueError, 'freshness window') as raised:
                module.saved_overrides(self.root, {})
            self.assertNotIn(str(value), str(raised.exception))

    def test_invalid_boolean_or_missing_configured_input_blocks(self):
        for value in ('secret text', [], 0):
            module = self.resolver(configured={'inputs': {'security_osv': value},
                                              'configured': ['security_osv']})
            with self.assertRaises(ValueError):
                module.saved_overrides(self.root, {})
        module = self.resolver(configured={'inputs': {}, 'configured': ['security_osv']})
        with self.assertRaises(ValueError):
            module.saved_overrides(self.root, {})

    def test_apply_mutates_only_missing_provider_environment(self):
        module = self.resolver()
        with patch.dict(os.environ, {'VS_SECURITY_OSV': 'true'}, clear=True):
            module.apply_saved_settings(self.root)
            self.assertEqual(os.environ['VS_SECURITY_OSV'], 'true')
            self.assertEqual(os.environ['VS_SECURITY_NPM_AUDIT'], 'true')

    def wrapper_fixture(self, fail=False, npm=True, real_engine=False):
        plugin = self.root / 'plugin with spaces'
        shutil.copytree(LIB.parent, plugin / 'scripts')
        marker = self.root / 'engine-ran'
        if npm:
            (self.root / 'package.json').write_text('{}')
        if not real_engine:
            (plugin / 'scripts/lib/security.py').write_text(
                'import os\nfrom pathlib import Path\n'
                'TRACKED={"package.json"}\n'
                'def resolve_path(value): return Path(value)\n'
                'def snapshot(root, config):\n'
                ' return {"files":{"package.json":"fixture"} if (root/"package.json").is_file() else {}}\n'
                'def run(args):\n'
                ' Path(os.environ["VS_SETTINGS_FIXTURE_MARKER"]).write_text("ran")\n'
                ' print(os.environ.get("VS_SECURITY_OSV", "unset"))\n'
                ' return 0\n'
                'if __name__ == "__main__":\n'
                ' import sys\n'
                ' sys.exit(run(sys.argv[1:]))\n')
        binary = self.root / 'fixture-bin'
        binary.mkdir()
        fixture = binary / 'fixture.py'
        fixture.write_text(
            'import json, os, sys\nfrom pathlib import Path\n'
            'with Path(os.environ["VS_SETTINGS_FIXTURE_CALLS"]).open("a") as log:\n'
            ' log.write(json.dumps(sys.argv[1:])+"\\n")\n'
            'if sys.argv[1:] == ["plugin", "list", "--json"]:\n'
            ' print(json.dumps([{"id":"version-sentinel@fixture",'
            '"installPath":os.environ["VS_SETTINGS_FIXTURE_ROOT"]}]))\n'
            'elif sys.argv[1:] == ["plugin", "configure", "version-sentinel@fixture", "--json"]:\n'
            ' if os.environ.get("VS_SETTINGS_FIXTURE_FAIL") == "1":\n'
            '  print("private unrelated option text", file=sys.stderr); sys.exit(1)\n'
            ' print(json.dumps({"inputs":{"security_osv":"false", "security_npm_audit":"true"},'
            '"configured":["security_osv","security_npm_audit"]}))\n'
            'else:\n'
            ' sys.exit(1)\n')
        if os.name == 'nt':
            launcher = binary / 'claude.cmd'
            launcher.write_text(f'@echo off\r\n"{sys.executable}" "{fixture}" %*\r\n')
        else:
            launcher = binary / 'claude'
            launcher.write_text('#!/bin/sh\nexec ' + shlex.quote(sys.executable) + ' ' +
                                shlex.quote(str(fixture)) + ' "$@"\n')
            launcher.chmod(0o755)
        environment = dict(os.environ)
        for key in ('VS_SECURITY_OSV', 'VS_SECURITY_NPM_AUDIT', 'VS_DISABLE',
                    'CLAUDE_PLUGIN_OPTION_SECURITY_OSV', 'CLAUDE_PLUGIN_OPTION_SECURITY_NPM_AUDIT',
                    'CLAUDE_PLUGIN_OPTION_DISABLE'):
            environment.pop(key, None)
        environment.update(PATH=str(binary) + os.pathsep + os.environ.get('PATH', ''),
                           VS_SETTINGS_FIXTURE_ROOT=str(plugin),
                           VS_SETTINGS_FIXTURE_MARKER=str(marker),
                           VS_SETTINGS_FIXTURE_CALLS=str(self.root / 'cli-calls'),
                           VS_SETTINGS_FIXTURE_FAIL='1' if fail else '0')
        bash = str(Path(shutil.which('bash')).resolve())
        self.wrapper_command = [bash, (plugin / 'scripts/security-check.sh').as_posix(), 'audit', str(self.root)]
        self.wrapper_environment = environment
        result = subprocess.run(self.wrapper_command, env=environment,
                                capture_output=True, text=True, timeout=30, check=False)
        return result, marker

    def test_wrapper_reads_saved_false_before_engine_runs(self):
        result, marker = self.wrapper_fixture()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), 'false')
        self.assertTrue(marker.is_file())

    def test_wrapper_lookup_failure_cannot_start_provider_engine(self):
        result, marker = self.wrapper_fixture(fail=True)
        self.assertEqual(result.returncode, 2, result.stderr)
        self.assertIn('unknown/incomplete', result.stderr)
        self.assertNotIn('private unrelated option text', result.stderr)
        self.assertFalse(marker.exists())

    def test_no_npm_audit_and_gate_skip_failing_claude_lookup(self):
        (self.root / 'requirements.txt').write_text('# Python-only fixture\n')
        result, _ = self.wrapper_fixture(fail=True, npm=False, real_engine=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse((self.root / 'cli-calls').exists())
        command = list(self.wrapper_command)
        command[-2] = 'gate'
        gate = subprocess.run(command, env=self.wrapper_environment, capture_output=True,
                              text=True, timeout=30, check=False)
        self.assertEqual(gate.returncode, 0, gate.stderr)
        self.assertFalse((self.root / 'cli-calls').exists())

    def test_deleted_npm_state_still_fails_engine_gate_without_cli_lookup(self):
        result, _ = self.wrapper_fixture(fail=True, npm=False, real_engine=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        state_path = self.root / '.version-sentinel/security.json'
        state = json.loads(state_path.read_text())
        state['status'] = 'complete'
        state['files'] = {'package.json': 'previous manifest hash'}
        state_path.write_text(json.dumps(state))
        command = list(self.wrapper_command)
        command[-2] = 'gate'
        gate = subprocess.run(command, env=self.wrapper_environment, capture_output=True,
                              text=True, timeout=30, check=False)
        self.assertEqual(gate.returncode, 2, gate.stderr)
        self.assertIn('project/settings changed', gate.stderr)
        self.assertFalse((self.root / 'cli-calls').exists())


if __name__ == '__main__':
    unittest.main()
