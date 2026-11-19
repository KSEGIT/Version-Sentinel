"""Local hook diagnostics must not query providers or manufacture scan evidence."""
import hashlib
import json
import os
from pathlib import Path
import shlex
import shutil
import subprocess
import sys
import tempfile
import time
import unittest


ROOT = Path(__file__).resolve().parents[1]


class LocalSecurityHookTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name).resolve()
        self.project = self.root / 'project'
        self.project.mkdir()
        (self.project / 'package.json').write_text('{"name":"local-fixture","dependencies":{}}')
        (self.project / 'package-lock.json').write_text(
            '{"name":"local-fixture","lockfileVersion":3,"packages":{"":{"name":"local-fixture","dependencies":{}}}}')
        self.state = self.project / '.version-sentinel/security.json'
        binary = self.root / 'bin'
        binary.mkdir()
        guard = self.root / 'guard'
        guard.mkdir()
        self.calls = self.root / 'external-calls'
        fixture = binary / 'forbidden.py'
        fixture.write_text(
            'import os,sys\nfrom pathlib import Path\n'
            'with Path(os.environ["VS_LOCAL_FIXTURE_CALLS"]).open("a") as log:\n'
            ' log.write("provider or Claude subprocess\\n")\n'
            'sys.exit(99)\n')
        for name in ('claude', 'npm'):
            if os.name == 'nt':
                (binary / (name + '.cmd')).write_text(
                    f'@echo off\r\n"{sys.executable}" "{fixture}" %*\r\n')
            else:
                launcher = binary / name
                launcher.write_text('#!/bin/sh\nexec ' + shlex.quote(sys.executable) +
                                    ' ' + shlex.quote(str(fixture)) + ' "$@"\n')
                launcher.chmod(0o755)
        (guard / 'sitecustomize.py').write_text(
            'import os,urllib.request\nfrom pathlib import Path\n'
            'def forbidden(*args, **kwargs):\n'
            ' with Path(os.environ["VS_LOCAL_FIXTURE_CALLS"]).open("a") as log:\n'
            '  log.write("upstream request\\n")\n'
            ' raise OSError("network forbidden in local-hook fixture")\n'
            'urllib.request.urlopen=forbidden\n')
        self.environment = dict(os.environ)
        for key in ('VS_SECURITY_OSV', 'VS_SECURITY_NPM_AUDIT', 'VS_DISABLE',
                    'VS_WINDOW_HOURS', 'VS_NOW_OVERRIDE', 'CLAUDE_PLUGIN_OPTION_WINDOW_HOURS',
                    'CLAUDE_PLUGIN_OPTION_SECURITY_OSV', 'CLAUDE_PLUGIN_OPTION_SECURITY_NPM_AUDIT',
                    'CLAUDE_PLUGIN_OPTION_DISABLE'):
            self.environment.pop(key, None)
        self.environment.update(VS_HOOK_LOCAL_ONLY='1',
                                VS_LOCAL_FIXTURE_CALLS=str(self.calls),
                                PATH=str(binary) + os.pathsep + os.environ.get('PATH', ''),
                                PYTHONPATH=str(guard))
        self.bash = str(Path(shutil.which('bash')).resolve())

    def invoke(self, script, *args, payload=None, timeout=5):
        try:
            return subprocess.run([self.bash, (ROOT / 'scripts' / script).as_posix(), *args],
                                  cwd=self.project, env=self.environment, input=payload,
                                  text=True, capture_output=True, timeout=timeout, check=False)
        except subprocess.TimeoutExpired:
            self.fail('local hook diagnostics waited for an external check or coalescer')

    def evidence(self):
        self.state.parent.mkdir(exist_ok=True)
        data = {'root': str(self.project), 'status': 'complete', 'checkedAt': time.time(),
                'providers': {'npm-audit': 'complete', 'osv': 'complete'}, 'findings': [],
                'settings': {'npm-audit': True, 'osv': True, 'window_hours': 24.0,
                             'block_level': 'high', 'unknown_severity': 'block', 'schema': 1},
                'files': {name: hashlib.sha256((self.project / name).read_bytes()).hexdigest()
                          for name in ('package.json', 'package-lock.json')}}
        self.state.write_text(json.dumps(data))
        return self.state.read_bytes()

    def assert_no_external_calls(self):
        self.assertFalse(self.calls.exists(), self.calls.read_text() if self.calls.exists() else '')

    def test_local_audit_without_evidence_reports_unknown_without_creating_evidence(self):
        result = self.invoke('security-check.sh', 'audit', str(self.project))
        self.assertEqual(result.returncode, 2, result.stdout + result.stderr)
        self.assert_no_external_calls()
        self.assertFalse(self.state.exists())

    def test_local_gate_and_audit_reuse_fresh_evidence_without_saved_settings_lookup(self):
        before = self.evidence()
        for action in ('gate', 'audit'):
            result = self.invoke('security-check.sh', action, str(self.project))
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assert_no_external_calls()
            self.assertEqual(self.state.read_bytes(), before)

    def test_local_proposals_report_unchecked_without_provider_calls_or_new_evidence(self):
        before = self.evidence()
        for arguments in (('proposed', str(self.project), 'local-fixture', '1.0.0'),
                          ('proposed-lock', str(self.project), str(self.project / 'package-lock.json'))):
            result = self.invoke('security-check.sh', *arguments, payload='{}')
            self.assertEqual(result.returncode, 2, result.stdout + result.stderr)
            self.assertIn('local', (result.stdout + result.stderr).lower())
            self.assert_no_external_calls()
            self.assertEqual(self.state.read_bytes(), before)

    def test_local_proposals_honor_disabled_osv_without_external_calls_or_new_evidence(self):
        before = self.evidence()
        for prefix in ('VS_', 'CLAUDE_PLUGIN_OPTION_'):
            for npm_audit in ('false', 'true'):
                with self.subTest(option_source=prefix, npm_audit=npm_audit):
                    self.environment[prefix + 'SECURITY_OSV'] = 'false'
                    self.environment[prefix + 'SECURITY_NPM_AUDIT'] = npm_audit
                    for arguments in (('proposed', str(self.project), 'local-fixture', '1.0.0'),
                                      ('proposed-lock', str(self.project), str(self.project / 'package-lock.json'))):
                        result = self.invoke('security-check.sh', *arguments, payload='{}')
                        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                        self.assertIn('disabled', result.stdout)
                        self.assertEqual(result.stderr, '')
                        self.assert_no_external_calls()
                        self.assertEqual(self.state.read_bytes(), before)
            self.environment.pop(prefix + 'SECURITY_OSV')
            self.environment.pop(prefix + 'SECURITY_NPM_AUDIT')

    def test_local_post_check_does_not_rescan_changed_tree(self):
        before = self.evidence()
        (self.project / 'package.json').write_text('{"name":"changed"}')
        payload = json.dumps({'cwd': str(self.project), 'tool_name': 'Bash',
                              'tool_input': {'command': 'echo unrelated'}})
        result = subprocess.run([sys.executable, str(ROOT / 'scripts/lib/security-post.py')],
                                cwd=self.project, env=self.environment, input=payload,
                                text=True, capture_output=True, timeout=5, check=False)
        self.assertEqual(result.returncode, 2, result.stdout + result.stderr)
        self.assert_no_external_calls()
        self.assertEqual(self.state.read_bytes(), before)

    def test_local_post_displays_cached_findings_without_claiming_a_fresh_scan(self):
        self.evidence()
        evidence = json.loads(self.state.read_text())
        evidence['findings'] = [{'package': 'local-fixture', 'ids': ['GHSA-local-fixture'],
                                 'severities': ['moderate'], 'providers': ['osv'],
                                 'links': ['https://osv.dev/vulnerability/GHSA-local-fixture']}]
        self.state.write_text(json.dumps(evidence))
        before = self.state.read_bytes()
        payload = json.dumps({'cwd': str(self.project), 'tool_name': 'Bash',
                              'tool_input': {'command': 'echo unrelated'}})
        result = subprocess.run([sys.executable, str(ROOT / 'scripts/lib/security-post.py')],
                                cwd=self.project, env=self.environment, input=payload,
                                text=True, capture_output=True, timeout=5, check=False)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('GHSA-local-fixture', result.stdout)
        self.assertIn('cached', result.stdout.lower())
        self.assert_no_external_calls()
        self.assertEqual(self.state.read_bytes(), before)

    def test_local_manifest_removal_does_not_lookup_saved_reconciliation_settings(self):
        manifest = {'name': 'local-fixture', 'dependencies': {'local-fixture': '1.0.0'}}
        (self.project / 'package.json').write_text(json.dumps(manifest))
        (self.project / 'package-lock.json').write_text(json.dumps({
            'name': 'local-fixture', 'lockfileVersion': 3, 'packages': {
                '': manifest, 'node_modules/local-fixture': {'version': '1.0.0',
                    'resolved': 'https://registry.npmjs.org/local-fixture/-/local-fixture-1.0.0.tgz'}}}))
        before = self.evidence()
        begin = self.invoke('audit-state.sh', 'begin', str(self.project))
        self.assertEqual(begin.returncode, 0, begin.stderr)
        complete = self.invoke('audit-state.sh', 'complete', str(self.project), begin.stdout)
        self.assertEqual(complete.returncode, 0, complete.stderr)
        payload = json.dumps({'cwd': str(self.project), 'tool_name': 'Write', 'tool_input': {
            'file_path': 'package.json', 'content': '{"name":"local-fixture","dependencies":{}}'}})
        result = subprocess.run([sys.executable, str(ROOT / 'scripts/lib/manifest-edit.py')],
                                cwd=self.project, env=self.environment, input=payload,
                                text=True, capture_output=True, timeout=5, check=False)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assert_no_external_calls()
        self.assertEqual(self.state.read_bytes(), before)

    def test_local_sidecar_lookup_does_not_wait_for_an_inflight_checker(self):
        temporary = self.root / 'coalescing'
        temporary.mkdir()
        (temporary / '.vs_coal_pip_local-fixture_1.0.0').write_text('fixture')
        self.environment.update(TMPDIR=str(temporary), VS_COALESCE_TTL='10')
        result = self.invoke('check-sidecar.sh', 'pip', 'local-fixture', '1.0.0', timeout=2)
        self.assertEqual(result.returncode, 2, result.stdout + result.stderr)
        self.assert_no_external_calls()


if __name__ == '__main__':
    unittest.main()
