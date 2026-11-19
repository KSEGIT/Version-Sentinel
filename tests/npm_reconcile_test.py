"""Guarded lock reconciliation uses exact pre-approved project transitions."""
import contextlib
import hashlib
import importlib
import importlib.util
import io
import json
import os
import re
import shutil
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

LIB = Path(__file__).resolve().parents[1] / 'scripts/lib'
sys.path.insert(0, str(LIB))


def module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result


def staged_fixture_summary(expected, staged):
    """Describe fixture differences without exposing arbitrary saved values."""
    public_fields = {'name', 'version', 'dependencies', 'devDependencies',
                     'optionalDependencies', 'peerDependencies', 'scripts', 'private'}

    def hashed(value):
        return hashlib.sha256(json.dumps(value, sort_keys=True, ensure_ascii=True).encode()).hexdigest()

    def parsed(raw):
        try:
            value = json.loads(raw)
            return value if isinstance(value, dict) else {}
        except (ValueError, UnicodeError):
            return {}

    before, after = parsed(expected), parsed(staged)
    changes = {}
    for key in sorted(before.keys() | after.keys()):
        left, right = before.get(key), after.get(key)
        if key in before and key in after and type(left) is type(right) and hashed(left) == hashed(right):
            continue
        label = key if key in public_fields else 'other-field-sha256:' + hashed(key)
        changes[label] = {
            'expected_type': type(left).__name__ if key in before else 'absent',
            'staged_type': type(right).__name__ if key in after else 'absent',
            'expected_sha256': hashed(left) if key in before else None,
            'staged_sha256': hashed(right) if key in after else None,
        }
        if key in {'dependencies', 'devDependencies', 'optionalDependencies', 'peerDependencies'}:
            for prefix, value in (('expected', left), ('staged', right)):
                if isinstance(value, dict):
                    changes[label][prefix + '_packages'] = [
                        name if name == 'lodash' else 'package-sha256:' + hashed(name)
                        for name in sorted(value)
                    ]
    return json.dumps({'changed_fields': changes,
                       'expected_bytes': len(expected), 'staged_bytes': len(staged),
                       'expected_sha256': hashlib.sha256(expected).hexdigest(),
                       'staged_sha256': hashlib.sha256(staged).hexdigest(),
                       'expected_bom': expected.startswith(b'\xef\xbb\xbf'),
                       'staged_bom': staged.startswith(b'\xef\xbb\xbf')}, sort_keys=True)


class ReconciliationTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name).resolve()
        self.env = patch.dict(os.environ, {'VS_SECURITY_NPM_AUDIT': 'true', 'VS_SECURITY_OSV': 'true', 'VS_WINDOW_HOURS': '24', 'VS_SESSION_ID': ''})
        self.env.start()
        self.addCleanup(self.env.stop)
        self.before = json.dumps({'name': 'fixture', 'dependencies': {'lodash': '4.17.21'}})
        self.after = json.dumps({'name': 'fixture', 'dependencies': {}})
        self.lock = json.dumps({'name': 'fixture', 'lockfileVersion': 3, 'packages': {'': json.loads(self.before), 'node_modules/lodash': {'version': '4.17.21', 'resolved': 'https://registry.npmjs.org/lodash/-/lodash-4.17.21.tgz'}}})
        self.new_lock = json.dumps({'name': 'fixture', 'lockfileVersion': 3, 'packages': {'': json.loads(self.after)}})
        self.manifest = self.root / 'package.json'
        self.lockpath = self.root / 'package-lock.json'
        self.manifest.write_bytes(self.before.encode())
        self.lockpath.write_bytes(self.lock.encode())

    def implementation(self):
        self.assertTrue((LIB / 'npm_reconcile.py').exists(), 'guarded reconciliation helper missing')
        rec = importlib.import_module('npm_reconcile')
        self.security = importlib.import_module('security')
        self.state = module('project_state_fixture', LIB / 'project-state.py')
        self.edit = module('manifest_edit_fixture', LIB / 'manifest-edit.py')
        config_patch = patch.object(rec, 'config', side_effect=self.security.settings)
        config_patch.start()
        self.addCleanup(config_patch.stop)
        self.rec = rec
        return rec

    def audited(self):
        rec = self.implementation()
        current = self.state.inventory(self.root, {})
        current.update(status='complete', checkedAt=self.state.now(), session='')
        self.state.write_json(self.state.state_path(self.root), current)
        with patch.object(self.security, 'npm_findings', return_value=[]), patch.object(self.security, 'osv_findings', return_value=[]), contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(self.security.audit(self.root, self.security.settings()), 0)
        return rec

    def approved_change(self):
        self.audited()
        self.edit.inspect(self.root, [(self.manifest, self.before, self.after)])
        self.manifest.write_bytes(self.after.encode())

    def test_removal_then_direct_lock_reconciliation_restores_auditable_tree(self):
        self.approved_change()
        with self.assertRaises(ValueError):
            self.security.gate(self.root, self.security.settings())
        original = self.edit.run
        def call(args, root, content=None):
            if 'proposed-lock' in args:
                self.rec.match_lock(root, self.lockpath, content)
                return subprocess.CompletedProcess(args, 0, '', '')
            return original(args, root, content)
        with patch.object(self.edit, 'run', side_effect=call):
            self.edit.inspect(self.root, [(self.lockpath, self.lock, self.new_lock)])
        self.lockpath.write_bytes(self.new_lock.encode())
        with patch.object(self.security, 'npm_findings', return_value=[]), patch.object(self.security, 'osv_findings', return_value=[]), contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(self.security.audit(self.root, self.security.settings()), 0)
        # Security scan alone does not manufacture a new startup/version audit.
        result = self.edit.state('gate', self.root, self.root)
        self.assertNotEqual(result.returncode, 0)
        current = self.state.inventory(self.root, {})
        current.update(status='complete', checkedAt=self.state.now(), session='')
        self.state.write_json(self.state.state_path(self.root), current)
        self.assertEqual(self.edit.state('gate', self.root, self.root).returncode, 0)

    def test_transition_rejects_unapproved_second_manifest_lock_config_time_and_project(self):
        for change in ('manifest', 'lock', 'config', 'time', 'other-file', 'root'):
            with self.subTest(change=change):
                self.manifest.write_bytes(self.before.encode())
                self.lockpath.write_bytes(self.lock.encode())
                other = self.root / 'requirements.txt'
                other.unlink(missing_ok=True)
                self.approved_change()
                if change == 'manifest': self.manifest.write_bytes(b'{"dependencies":{"extra":"1.0.0"}}')
                if change == 'lock': self.lockpath.write_bytes(b'{}')
                if change == 'other-file': other.write_bytes(b'other==1.0.0')
                if change == 'root':
                    record = json.loads((self.root / '.version-sentinel/reconcile.json').read_text())
                    record['root'] = str(self.root / 'other')
                    (self.root / '.version-sentinel/reconcile.json').write_text(json.dumps(record))
                env = {'VS_SECURITY_OSV': 'false'} if change == 'config' else {'VS_NOW_OVERRIDE': '2099-01-01T00:00:00Z'} if change == 'time' else {}
                with patch.dict(os.environ, env), self.assertRaises(ValueError):
                    self.rec.permit(self.root, self.lockpath)

    def test_proposed_lock_root_must_match_the_approved_manifest(self):
        self.approved_change()
        with self.assertRaises(ValueError):
            self.rec.match_lock(self.root, self.lockpath, self.lock)

    def test_explicit_regeneration_checks_temp_postimage_before_real_write_and_full_audit(self):
        self.approved_change()
        calls = []
        def run(args, **kwargs):
            calls.append(args)
            if 'install' in args:
                staging = Path(kwargs['cwd'])
                self.assertNotEqual(staging, self.root)
                self.assertIn('--package-lock-only', args)
                self.assertIn('--ignore-scripts', args)
                (staging / 'package-lock.json').write_bytes(self.new_lock.encode())
            elif 'proposed-lock' in args:
                self.assertEqual(self.lockpath.read_text(), self.lock)
                self.assertEqual(kwargs['input'], self.new_lock)
            if 'install' in args:
                return subprocess.CompletedProcess(args, 0, 'npm staged output\n', 'npm staged note\n')
            if 'proposed-lock' in args:
                return subprocess.CompletedProcess(args, 0, 'GHSA-stage-low LOW https://osv.dev/vulnerability/GHSA-stage-low affected <2 fixed 2 provider osv\n', 'GHSA-stage-moderate MODERATE https://osv.dev/vulnerability/GHSA-stage-moderate affected <3 fixed 3 provider npm-audit\n')
            return subprocess.CompletedProcess(args, 0, 'full audit output once\n', '')
        stdout, stderr = io.StringIO(), io.StringIO()
        with patch.object(self.rec, 'command', side_effect=run), patch.object(self.rec.shutil, 'which', return_value='/fixture/executable'), contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(stderr):
            self.rec.regenerate(self.root, self.manifest)
        self.assertIn('npm staged output', stdout.getvalue())
        self.assertIn('npm staged note', stderr.getvalue())
        self.assertIn('GHSA-stage-low LOW https://osv.dev/vulnerability/GHSA-stage-low affected <2 fixed 2 provider osv', stdout.getvalue())
        self.assertIn('GHSA-stage-moderate MODERATE https://osv.dev/vulnerability/GHSA-stage-moderate affected <3 fixed 3 provider npm-audit', stderr.getvalue())
        self.assertEqual(stdout.getvalue().count('full audit output once'), 1)
        self.assertEqual(self.lockpath.read_text(), self.new_lock)
        self.assertTrue(any('check-versions.sh' in str(arg) for args in calls for arg in args))
        self.assertFalse(any('fix' == arg for args in calls for arg in args))

    def test_staged_manifest_formatting_does_not_change_the_approved_project(self):
        self.approved_change()
        original = self.manifest.read_bytes()
        reformatted = (json.dumps(json.loads(self.after), indent=2, sort_keys=True)
                       .replace('\n', '\r\n') + '\r\n').encode()
        self.assertNotEqual(reformatted, original)

        def run(args, **kwargs):
            if 'install' in args:
                staging = Path(kwargs['cwd'])
                (staging / 'package.json').write_bytes(reformatted)
                (staging / 'package-lock.json').write_bytes(self.new_lock.encode())
            return subprocess.CompletedProcess(args, 0, '', '')

        with patch.object(self.rec, 'command', side_effect=run), patch.object(self.rec.shutil, 'which', return_value='/fixture/executable'), contextlib.redirect_stdout(io.StringIO()):
            self.rec.regenerate(self.root, self.manifest)
        self.assertEqual(self.manifest.read_bytes(), original)
        self.assertEqual(self.lockpath.read_bytes(), self.new_lock.encode())

    def test_regeneration_keeps_local_and_global_prefixes_distinct(self):
        self.approved_change()
        outside = self.root / 'must-not-be-used-as-prefix'
        calls = []

        def run(args, **kwargs):
            calls.append(args)
            if 'install' in args:
                staging = Path(kwargs['cwd'])
                # npm 10 compares its local prefix with globalTop even when
                # global=false. A CLI prefix makes these equal on Windows.
                self.assertFalse(any(arg == '--prefix' or str(arg).startswith('--prefix=') for arg in args))
                self.assertIn('--global=false', args)
                self.assertIn('--location=project', args)
                environment = kwargs['env']
                prefix_keys = [key for key in environment if key.lower() == 'npm_config_prefix']
                self.assertEqual(prefix_keys, ['npm_config_prefix'])
                private_prefix = Path(environment['npm_config_prefix'])
                self.assertEqual(private_prefix.parent, staging)
                self.assertNotEqual(private_prefix, staging)
                self.assertNotEqual(private_prefix, outside)
                (staging / 'package-lock.json').write_bytes(self.new_lock.encode())
            return subprocess.CompletedProcess(args, 0, '', '')

        original_environment = {'npm_config_prefix': str(outside),
                                'NPM_CONFIG_PREFIX': str(outside),
                                'Npm_Config_Prefix': str(outside),
                                'npm_config_global': 'true',
                                'npm_config_location': 'global'}
        with patch.dict(os.environ, original_environment), patch.object(self.rec, 'command', side_effect=run), patch.object(self.rec.shutil, 'which', return_value='/fixture/executable'), contextlib.redirect_stdout(io.StringIO()):
            self.rec.regenerate(self.root, self.manifest)
            for key, value in original_environment.items():
                self.assertEqual(os.environ[key], value)
        self.assertTrue(any('install' in args for args in calls))
        self.assertEqual(self.manifest.read_bytes(), self.after.encode())
        self.assertFalse(outside.exists())

    def test_staged_npm_empty_dependency_table_pruning_is_safe(self):
        self.after = json.dumps({'name': 'fixture', **{key: {} for key in ('dependencies', 'devDependencies', 'optionalDependencies', 'peerDependencies')}})
        self.approved_change()
        original = self.manifest.read_bytes()

        def run(args, **kwargs):
            if 'install' in args:
                staging = Path(kwargs['cwd'])
                (staging / 'package.json').write_bytes(b'{"name":"fixture"}\r\n')
                (staging / 'package-lock.json').write_bytes(self.new_lock.encode())
            return subprocess.CompletedProcess(args, 0, '', '')

        with patch.object(self.rec, 'command', side_effect=run), patch.object(self.rec.shutil, 'which', return_value='/fixture/executable'), contextlib.redirect_stdout(io.StringIO()):
            self.rec.regenerate(self.root, self.manifest)
        self.assertEqual(self.manifest.read_bytes(), original)
        self.assertEqual(self.lockpath.read_bytes(), self.new_lock.encode())

    def test_staged_manifest_meaning_changes_never_replace_the_real_lock(self):
        self.after = json.dumps({'name': 'fixture', 'dependencies': {}, 'private': True})
        self.approved_change()
        original = self.manifest.read_bytes()
        changed = [
            json.dumps({'name': 'fixture', 'dependencies': {'extra': '1.0.0'}, 'private': True}),
            json.dumps({'name': 'fixture', 'dependencies': {}, 'private': True, 'scripts': {'install': 'unexpected'}}),
            json.dumps({'name': 'other', 'dependencies': {}, 'private': True}),
            json.dumps({'name': 'fixture', 'dependencies': {}, 'private': 1}),
            json.dumps({'name': 'fixture', 'dependencies': [], 'private': True}),
            '{"name":"fixture","private":true,"dependencies":{},"dependencies":{}}',
        ]
        for replacement in changed:
            with self.subTest(replacement=replacement):
                def run(args, **kwargs):
                    if 'install' in args:
                        staging = Path(kwargs['cwd'])
                        (staging / 'package.json').write_bytes(replacement.encode())
                        (staging / 'package-lock.json').write_bytes(self.new_lock.encode())
                    return subprocess.CompletedProcess(args, 0, '', '')
                with patch.object(self.rec, 'command', side_effect=run), patch.object(self.rec.shutil, 'which', return_value='/fixture/executable'), self.assertRaises(ValueError):
                    self.rec.regenerate(self.root, self.manifest)
                self.assertEqual(self.manifest.read_bytes(), original)
                self.assertEqual(self.lockpath.read_bytes(), self.lock.encode())

    def test_atomic_manifest_and_lock_edit_does_not_leave_reconciliation_authority(self):
        self.audited()
        changes = [(self.manifest, self.before, self.after), (self.lockpath, self.lock, self.new_lock)]
        self.rec.authorize(self.root, changes, [changes[0]])
        self.assertFalse(self.rec.record_path(self.root).exists())

    def test_multiple_npm_projects_require_separate_approved_transitions(self):
        self.audited()
        child = self.root / 'child'
        child.mkdir()
        (child / 'package.json').write_bytes(self.before.encode())
        (child / 'package-lock.json').write_bytes(self.lock.encode())
        # A new inventory must first receive its own clean audit.
        current = self.state.inventory(self.root, {})
        current.update(status='complete', checkedAt=self.state.now(), session='')
        self.state.write_json(self.state.state_path(self.root), current)
        with patch.object(self.security, 'npm_findings', return_value=[]), patch.object(self.security, 'osv_findings', return_value=[]), contextlib.redirect_stdout(io.StringIO()):
            self.security.audit(self.root, self.security.settings())
        changes = [(self.manifest, self.before, self.after), (child / 'package.json', self.before, self.after)]
        with self.assertRaisesRegex(ValueError, 'one npm project at a time'):
            self.rec.authorize(self.root, changes, changes)

    def test_external_command_failure_is_not_suppressed(self):
        self.implementation()
        with patch.object(self.rec.subprocess, 'run', return_value=subprocess.CompletedProcess([], 2, 'HIGH GHSA-fixture', 'provider failed')), self.assertRaisesRegex(ValueError, 'GHSA-fixture'):
            self.rec.command(['fixture'])

    @unittest.skipUnless(shutil.which('npm'), 'npm is required for the real scriptless resolver smoke')
    def test_real_scriptless_lock_regeneration_after_approved_removal(self):
        version = subprocess.run([shutil.which('npm'), '--version'], capture_output=True,
                                 text=True, timeout=30, check=False)
        safe_version = version.stdout.strip()
        if version.returncode or not re.fullmatch(r'\d+\.\d+\.\d+(?:-[A-Za-z0-9.-]+)?', safe_version):
            safe_version = 'unavailable'
        print(f'reconciliation fixture: npm={safe_version} platform={sys.platform}', file=sys.stderr)
        for newline in ('\n', '\r\n'):
            with self.subTest(newline=repr(newline)):
                self.manifest.write_bytes(self.before.encode())
                self.lockpath.write_bytes(self.lock.encode())
                self.after = json.dumps({'name': 'fixture', 'dependencies': {}}, indent=2).replace('\n', newline) + newline
                self.approved_change()
                expected = self.manifest.read_bytes()
                original_content = self.rec.manifest_content
                expected_content = original_content(expected)

                def diagnostic_content(raw):
                    try:
                        result = original_content(raw)
                    except (ValueError, UnicodeError):
                        print('reconciliation fixture staged mismatch: ' + staged_fixture_summary(expected, raw), file=sys.stderr)
                        raise
                    if result != expected_content:
                        print('reconciliation fixture staged mismatch: ' + staged_fixture_summary(expected, raw), file=sys.stderr)
                    return result

                # Removing the sole dependency needs no registry resolution.
                # Force offline mode to prohibit accidental registry requests.
                with patch.dict(os.environ, {'npm_config_offline': 'true'}), patch.object(self.rec, 'manifest_content', side_effect=diagnostic_content), contextlib.redirect_stdout(io.StringIO()):
                    self.rec.regenerate(self.root, self.manifest)
                self.assertEqual(self.manifest.read_bytes(), self.after.encode())
                self.assertEqual(json.loads(self.lockpath.read_text())['packages'][''].get('dependencies', {}), {})
                self.assertFalse((self.root / 'node_modules').exists())
                self.assertEqual(self.edit.state('gate', self.root, self.root).returncode, 0)
                self.assertFalse(self.rec.record_path(self.root).exists())

    def test_failed_proposal_or_changed_inputs_never_replace_actual_lock(self):
        for failure in ('provider', 'changed'):
            self.manifest.write_bytes(self.before.encode())
            self.lockpath.write_bytes(self.lock.encode())
            self.approved_change()
            def run(args, **kwargs):
                if 'install' in args:
                    (Path(kwargs['cwd']) / 'package-lock.json').write_bytes(self.new_lock.encode())
                    if failure == 'changed': self.manifest.write_bytes(b'{}')
                if failure == 'provider' and 'proposed-lock' in args:
                    raise ValueError('fixture provider failure')
                return subprocess.CompletedProcess(args, 0, '', '')
            with patch.object(self.rec, 'command', side_effect=run), patch.object(self.rec.shutil, 'which', return_value='/fixture/executable'), self.assertRaises(ValueError):
                self.rec.regenerate(self.root, self.manifest)
            self.assertEqual(self.lockpath.read_text(), self.lock)


if __name__ == '__main__':
    unittest.main()
