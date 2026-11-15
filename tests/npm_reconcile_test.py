"""Guarded lock reconciliation uses exact pre-approved project transitions."""
import contextlib
import importlib
import importlib.util
import io
import json
import os
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
        self.approved_change()
        # Removing the sole dependency needs no registry resolution. Force
        # offline mode so this test cannot contact a registry even by mistake.
        with patch.dict(os.environ, {'npm_config_offline': 'true'}), contextlib.redirect_stdout(io.StringIO()):
            self.rec.regenerate(self.root, self.manifest)
        self.assertEqual(self.manifest.read_text(), self.after)
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
