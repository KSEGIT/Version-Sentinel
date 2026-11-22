"""Public tool hooks remember advisories without changing validation."""
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


SCRIPTS = Path(__file__).resolve().parents[1] / 'scripts'
POST = 'auto-record.sh'
INSTALL = 'detect-install-cmd.sh'
EDIT = 'detect-manifest-edit.sh'
HISTORY = '.version-sentinel/warning-history.json'


class WarningDedupTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name).resolve()
        self.project = self.make_project('project')
        self.environment = {
            **os.environ, 'VS_DISABLE': '0', 'VS_SECURITY_NPM_AUDIT': '1', 'VS_SECURITY_OSV': '1',
            'VS_WINDOW_HOURS': '24', 'VS_NOW_OVERRIDE': '2026-11-22T10:00:00Z',
        }
        self.environment.pop('VS_PROJECT_ROOT', None)
        self.bash = str(Path(shutil.which('bash')).resolve())

    def make_project(self, name):
        project = self.root / name
        project.mkdir()
        (project / 'package.json').write_text('{"name":"fixture","dependencies":{}}')
        return project

    def evidence(self, name, data):
        path = self.project / '.version-sentinel' / name
        path.parent.mkdir(exist_ok=True)
        path.write_text(json.dumps(data))
        return path

    def security_evidence(self, findings=()):
        return self.evidence('security.json', {
            'root': str(self.project), 'status': 'complete', 'checkedAt': 1795341600,
            'settings': {'npm-audit': True, 'osv': True, 'window_hours': 24.0,
                         'block_level': 'high', 'unknown_severity': 'block', 'schema': 1},
            'files': {'package.json': hashlib.sha256((self.project / 'package.json').read_bytes()).hexdigest()},
            'findings': list(findings),
        })

    def hook(self, script=POST, command='ls', *, project=None, workdir=None, mode=None,
             content=None, scripts=SCRIPTS, raw=None, timeout=20, **environment):
        project = self.project if project is None else project
        shell = 'run_shell_command' if mode == '--gemini' else 'exec_command'
        data = {'command': command}
        if workdir is not None:
            data['workdir'] = str(workdir)
        if content is not None:
            shell = 'Write'
            data = {'file_path': 'package.json', 'content': content}
        payload = json.dumps({'tool_name': shell, 'cwd': str(project), 'tool_input': data})
        args = [self.bash, (scripts / script).as_posix()]
        if mode:
            args.append(mode)
        result = subprocess.run(args, cwd=self.root, input=payload if raw is None else raw,
                                text=True, capture_output=True, timeout=timeout,
                                env={**self.environment, **environment}, check=False)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stderr, '')
        return result.stdout

    def assert_warning(self, output):
        message = json.loads(output or '{}').get('systemMessage', '')
        self.assertIn('WARNING: Version Sentinel', message)
        self.assertIn('Work may continue', message)
        return message

    def test_different_read_commands_share_the_first_warning(self):
        self.assert_warning(self.hook(command='ls'))
        self.assertEqual(self.hook(command='cat package.json'), '')
        self.assertEqual(self.hook(command='rg dependencies package.json'), '')
        for name in ('audit.json', 'checks.json', 'security.json'):
            self.assertFalse((self.project / '.version-sentinel' / name).exists())

    def test_dependency_files_and_each_evidence_file_change_the_warning(self):
        self.assert_warning(self.hook())
        (self.project / 'unrelated.txt').write_text('new documentation')
        self.assertEqual(self.hook(), '')
        for name in ('package.json', 'package-lock.json', 'Cargo.toml', '.npmrc'):
            with self.subTest(file=name):
                (self.project / name).write_text('{}\n')
                self.assert_warning(self.hook())
                self.assertEqual(self.hook(), '')
        for name in ('audit.json', 'checks.json', 'security.json'):
            with self.subTest(evidence=name):
                self.evidence(name, {'status': 'pending'})
                self.assert_warning(self.hook())
                self.assertEqual(self.hook(), '')

    def test_setting_changes_rearm_the_warning(self):
        self.assert_warning(self.hook())
        self.assertEqual(self.hook(), '')
        self.assert_warning(self.hook(VS_WINDOW_HOURS='48'))
        self.assertEqual(self.hook(VS_WINDOW_HOURS='48'), '')
        self.assert_warning(self.hook(VS_WINDOW_HOURS='48', VS_SECURITY_OSV='0'))
        self.assert_warning(self.hook())

    def test_successful_local_check_rearms_an_earlier_warning(self):
        evidence = self.security_evidence()
        before = evidence.read_bytes()
        expired = {'VS_NOW_OVERRIDE': '2026-11-24T10:00:00Z'}
        self.assert_warning(self.hook(**expired))
        self.assertEqual(self.hook(**expired), '')
        self.assertEqual(self.hook(), '')
        self.assert_warning(self.hook(**expired))
        self.assertEqual(self.hook(**expired), '')
        self.assertEqual(evidence.read_bytes(), before)

    def test_skipped_precheck_does_not_rearm_an_install_warning(self):
        self.assert_warning(self.hook(INSTALL, 'npm test'))
        self.assertEqual(self.hook(INSTALL, 'ls'), '')
        self.assertEqual(self.hook(INSTALL, 'npm run test'), '')

    def test_workdir_and_literal_cd_use_their_effective_project(self):
        alternate = self.make_project('other project')
        self.assert_warning(self.hook())
        self.assert_warning(self.hook(workdir=alternate))
        self.assertEqual(self.hook(project=alternate, command='cat package.json'), '')
        self.assertEqual(self.hook(project=self.root, command="cd 'other project' && ls"), '')
        (alternate / 'package.json').write_text('{"name":"changed"}')
        self.assert_warning(self.hook(project=self.root, command="cd 'other project' && cat package.json"))
        self.assertEqual(self.hook(project=self.root, command="cd 'other project' && ls"), '')
        self.assertEqual(self.hook(), '')
        self.assert_warning(self.hook(INSTALL, "cd 'other project' && npm test", project=self.root))
        self.assertEqual(self.hook(INSTALL, 'npm run test', project=alternate), '')

    def test_nested_read_preserves_parent_project_warning(self):
        (self.project / 'scripts').mkdir()
        self.assert_warning(self.hook(command='cd scripts && cat ../package.json'))
        self.assertEqual(self.hook(command='cat package.json'), '')
        self.assertEqual(self.hook(command='cd scripts && ls'), '')

    def test_unrelated_proposed_installs_and_edits_each_warn(self):
        for command in ('npm install lodash@4.17.21', 'npm install express@4.19.2'):
            self.assert_warning(self.hook(INSTALL, command))
            self.assertEqual(self.hook(INSTALL, command), '')
        self.assertEqual(self.hook(INSTALL, 'npm install lodash@4.17.21'), '')
        for version in ('1.0.0', '2.0.0'):
            content = json.dumps({'dependencies': {'lodash': version}})
            self.assert_warning(self.hook(EDIT, content=content))
            self.assertEqual(self.hook(EDIT, content=content), '')

    def test_corrupt_or_unavailable_history_keeps_warnings_visible(self):
        path = self.project / HISTORY
        path.parent.mkdir()
        path.write_text('corrupt data')
        for _ in range(2):
            self.assert_warning(self.hook())
        self.assertEqual(path.read_text(), 'corrupt data')
        path.unlink()
        path.mkdir()
        for _ in range(2):
            self.assert_warning(self.hook())
        self.assertTrue(path.is_dir())

    def test_unsupported_payload_keeps_warnings_visible(self):
        for _ in range(2):
            self.assert_warning(self.hook(INSTALL, raw='invalid json'))

    def test_malformed_payload_bytes_reach_the_validator(self):
        payload = json.dumps({'cwd': str(self.project), 'tool_name': 'Bash',
                              'tool_input': {'command': 'ls'}}) + '\x00'
        self.assertIn('Extra data', self.assert_warning(self.hook(raw=payload)))

    def test_busy_history_lock_keeps_warnings_visible(self):
        path = (self.project / HISTORY).with_suffix('.lock')
        path.parent.mkdir()
        with path.open('a+b') as handle:
            if os.name == 'nt':
                import msvcrt
                msvcrt.locking(handle.fileno(), msvcrt.LK_NBLCK, 1)
            else:
                import fcntl
                fcntl.flock(handle.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
            self.assert_warning(self.hook(timeout=4))

    def test_concurrent_hooks_record_distinct_advisories_once(self):
        commands = ['npm install lodash@4.17.21', 'npm install express@4.19.2'] * 4
        with ThreadPoolExecutor(max_workers=8) as pool:
            results = list(pool.map(lambda command: self.hook(INSTALL, command), commands))
        for command in set(commands):
            warnings = [value for key, value in zip(commands, results) if key == command and value]
            self.assertEqual(len(warnings), 1, (command, warnings))
            self.assert_warning(warnings[0])
            self.assertEqual(self.hook(INSTALL, command), '')

    def test_findings_and_platform_output_survive_deduplication(self):
        for identifier, mode in (('GHSA-first', '--gemini'), ('GHSA-second', '--copilot')):
            with self.subTest(identifier=identifier):
                link = 'https://osv.dev/vulnerability/' + identifier
                self.security_evidence([{'ids': [identifier], 'links': [link], 'title': 'quoted "advisory"'}])
                output = self.hook(mode=mode)
                message = self.assert_warning(output)
                details = json.loads(message.split('security finding: ', 1)[1])
                self.assertEqual(details['ids'], [identifier])
                self.assertEqual(details['links'], [link])
                self.assertEqual(details['title'], 'quoted "advisory"')
                formatted = json.loads(output)
                if mode == '--gemini':
                    self.assertEqual(formatted, {'systemMessage': message})
                else:
                    self.assertEqual(formatted, {
                        'systemMessage': message, 'additionalContext': message,
                        'hookSpecificOutput': {'hookEventName': 'PostToolUse', 'additionalContext': message},
                    })
                self.assertEqual(self.hook(mode=mode), '')

    def test_changed_diagnostics_rewarn_without_changed_project_state(self):
        scripts = self.root / 'fixture-scripts'
        shutil.copytree(SCRIPTS, scripts)
        # Replace only the diagnostic producer to simulate changed findings
        # from identical evidence. Still run the public wrapper and real cache.
        (scripts / 'validate-auto-record.sh').write_text(
            'printf \'security finding: {"ids":["%s"]}\\n\' "$FINDING" >&2\n')
        self.assertIn('GHSA-old', self.assert_warning(self.hook(scripts=scripts, FINDING='GHSA-old')))
        self.assertEqual(self.hook(scripts=scripts, FINDING='GHSA-old'), '')
        self.assertIn('GHSA-new', self.assert_warning(self.hook(scripts=scripts, FINDING='GHSA-new')))
        self.assertIn('GHSA-old', self.assert_warning(self.hook(scripts=scripts, FINDING='GHSA-old')))
        self.assertEqual(self.hook(scripts=scripts, FINDING='GHSA-old'), '')

    def test_first_and_duplicate_warnings_make_no_network_request(self):
        guard = self.root / 'no-network'
        guard.mkdir()
        calls = guard / 'calls'
        (guard / 'sitecustomize.py').write_text(
            'import os, socket\nfrom pathlib import Path\n'
            'def forbidden(*args, **kwargs):\n'
            ' Path(os.environ["NETWORK_CALLS"]).touch()\n'
            ' raise OSError("network access from a local hook")\n'
            'socket.create_connection = forbidden\nsocket.socket.connect = forbidden\n')
        for name in ('curl', 'npm', 'claude'):
            launcher = guard / name
            launcher.write_text('#!/usr/bin/env bash\n: > "$NETWORK_CALLS"\nexit 99\n')
            launcher.chmod(0o755)
        environment = {
            'PYTHONPATH': str(guard), 'NETWORK_CALLS': str(calls),
            'PATH': str(guard) + os.pathsep + self.environment['PATH'],
        }
        self.assert_warning(self.hook(**environment))
        self.assertEqual(self.hook(**environment), '')
        self.assertFalse(calls.exists())


if __name__ == '__main__':
    unittest.main()
