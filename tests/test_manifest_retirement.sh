#!/usr/bin/env bash
# Exercise the public command against real temporary Git repositories.
set -eu
VS_RETIRE_TEST_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# Pass the root through argv so Git Bash maps it for native Windows Python.
python3 - "$VS_RETIRE_TEST_ROOT" <<'PY'
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import time
import tempfile
import unittest

PLUGIN = Path(sys.argv.pop())
# Native CreateProcess may select the WSL launcher for bare "bash" before PATH.
BASH = shutil.which('bash')
assert BASH is not None, 'Git Bash is required for the retirement fixture'
BASH = str(Path(BASH).resolve())

class ManifestRetirement(unittest.TestCase):
    def setUp(self):
        # This fixture exercises Git retirement and version-registry evidence;
        # advisory-provider coverage has its own lockfile-backed fixtures.
        self.environment = dict(os.environ, VS_SECURITY_NPM_AUDIT='0', VS_SECURITY_OSV='0')
        self.tmp = tempfile.TemporaryDirectory(prefix='vs-retirement-')
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.repo = self.root / 'work' / 'project'
        self.repo.mkdir(parents=True)
        self.file = 'work/project/requirements-seed.txt'
        self.target = self.root / self.file
        self.target.write_bytes(b'# deliberately retired\n')
        (self.repo / 'package.json').write_text('{"dependencies":{"lodash":"4.17.21"}}')
        self.git('init', '-q')
        self.git('config', 'user.email', 'fixture@example.invalid')
        self.git('config', 'user.name', 'Fixture')
        self.git('add', '.')
        self.git('commit', '-qm', 'initial')
        self.initial = self.git('rev-parse', 'HEAD').stdout.strip()
        started = self.state('begin')
        self.assertEqual(0, started.returncode, started.stdout + started.stderr)
        self.git('rm', '-q', 'requirements-seed.txt')
        self.git('commit', '-qm', 'deliberately retire seed requirements')
        self.deleted = self.git('rev-parse', 'HEAD').stdout.strip()

    def git(self, *args, check=True):
        return subprocess.run(['git', '-C', str(self.repo), *args], capture_output=True, text=True, check=check)

    def state(self, *args):
        return subprocess.run([BASH, (PLUGIN / 'scripts/audit-state.sh').as_posix(), args[0], str(self.root), *args[1:]], env=self.environment, capture_output=True, text=True)

    def retire(self, *args):
        if not args:
            args = (self.file, '--deleted-by', self.deleted, '--user-confirmed', 'Daniel approved this committed deletion')
        return subprocess.run([BASH, (PLUGIN / 'scripts/retire-manifest.sh').as_posix(), *args], cwd=self.root, capture_output=True, text=True)

    def read_state(self):
        return json.loads((self.root / '.version-sentinel/audit.json').read_text())

    def assert_blocked_unchanged(self, *args):
        before = self.read_state()
        result = self.retire(*args)
        self.assertEqual(2, result.returncode, result.stdout + result.stderr)
        self.assertEqual(before, self.read_state())

    def audit(self, fail=False):
        bindir = self.root / 'bin'
        bindir.mkdir(exist_ok=True)
        curl = bindir / 'curl'
        curl.write_bytes(('#!/usr/bin/env bash\n' + ('exit 7\n' if fail else 'printf \'%s\\n\' \'{"name":"lodash","dist-tags":{"latest":"4.17.21"},"versions":{"4.17.21":{}}}\'\n')).encode())
        curl.chmod(0o755)
        env = dict(self.environment, PATH=str(bindir) + os.pathsep + os.environ['PATH'], VS_ETAG_DISABLE='1', VS_REGISTRY_RETRIES='1', VS_REGISTRY_RETRY_DELAY='0')
        return subprocess.run([BASH, (PLUGIN / 'scripts/check-versions.sh').as_posix()], cwd=self.root, env=env, capture_output=True, text=True)

    def test_committed_retirement_keeps_other_paths_and_requires_fresh_online_audit(self):
        old_generation = self.read_state()['generation']
        result = self.retire()
        self.assertEqual(0, result.returncode, result.stdout + result.stderr)
        state = self.read_state()
        self.assertEqual(['work/project/package.json'], state['required'])
        self.assertNotIn(self.file, state['files'])
        self.assertEqual('pending', state['status'])
        self.assertNotEqual(old_generation, state['generation'])
        receipt = state['retirements'][0]
        self.assertEqual(self.file, receipt['file'])
        self.assertEqual(self.deleted, receipt['deletionCommit'])
        self.assertEqual(self.deleted, receipt['head'])
        self.assertEqual(hashlib.sha256(b'# deliberately retired\n').hexdigest(), receipt['previousFileHash'])
        self.assertEqual('Daniel approved this committed deletion', receipt['reason'])
        self.assertGreater(receipt['approvedAt'], 0)
        self.assertEqual(2, self.state('gate').returncode)
        self.assertEqual(2, self.audit(fail=True).returncode)
        self.assertEqual(2, self.state('gate').returncode)
        result = self.audit()
        self.assertEqual(0, result.returncode, result.stdout + result.stderr)
        self.assertEqual(0, self.state('gate').returncode)
        self.assertEqual([receipt], self.read_state()['retirements'])
        self.assertFalse((self.root / '.version-sentinel/checks.json').exists())
        self.target.write_text('')
        self.assertEqual(2, self.state('gate').returncode)
        result = self.audit()
        self.assertEqual(0, result.returncode, result.stdout + result.stderr)
        self.assertIn(self.file, self.read_state()['required'])
        self.target.unlink()
        self.assertEqual(2, self.state('gate').returncode)

    def test_approval_and_exact_commit_are_required(self):
        for args in [
            (self.file, '--deleted-by', self.deleted),
            (self.file, '--deleted-by', self.deleted, '--user-confirmed', '  '),
            (self.file, '--deleted-by', 'HEAD', '--user-confirmed', 'approved'),
            (self.file, '--deleted-by', self.initial, '--user-confirmed', 'approved'),
            (self.file, '--deleted-by', 'f' * 40, '--user-confirmed', 'approved'),
            ('../requirements.txt', '--deleted-by', self.deleted, '--user-confirmed', 'approved'),
            ('work/project/requirements-unknown.txt', '--deleted-by', self.deleted, '--user-confirmed', 'approved'),
        ]:
            with self.subTest(args=args):
                self.assert_blocked_unchanged(*args)

    def test_uncommitted_and_staged_deletions_are_blocked(self):
        self.git('reset', '--hard', self.initial)
        self.target.unlink()
        self.assert_blocked_unchanged()
        self.git('add', '-u')
        self.assert_blocked_unchanged()

    def test_existing_and_staged_recreated_files_are_blocked(self):
        self.target.write_text('')
        self.assert_blocked_unchanged()
        self.git('add', 'requirements-seed.txt')
        self.target.unlink()
        self.assert_blocked_unchanged()

    def test_wrong_deletion_commit_and_references_are_blocked(self):
        self.git('commit', '--allow-empty', '-qm', 'unrelated')
        unrelated = self.git('rev-parse', 'HEAD').stdout.strip()
        self.assert_blocked_unchanged(self.file, '--deleted-by', unrelated, '--user-confirmed', 'approved')
        (self.repo / 'requirements.txt').write_text('-r requirements-seed.txt\n')
        self.assert_blocked_unchanged()

    def test_deletion_outside_head_history_is_blocked(self):
        self.git('reset', '--hard', self.initial)
        self.git('rm', '-q', 'requirements-seed.txt')
        self.git('commit', '-qm', 'different deletion', '--date=2000-01-01T00:00:00Z')
        self.assert_blocked_unchanged()

    def test_stale_inflight_audit_cannot_complete_after_retirement(self):
        started = self.read_state()
        result = self.retire()
        self.assertEqual(0, result.returncode, result.stdout + result.stderr)
        self.assertEqual(2, self.state('complete', json.dumps(started)).returncode)

    def test_other_missing_required_manifest_is_retained(self):
        other = self.repo / 'requirements-other.txt'
        other.write_text('')
        self.state('begin')
        other.unlink()
        result = self.retire()
        self.assertEqual(0, result.returncode, result.stdout + result.stderr)
        self.assertEqual(['work/project/package.json', 'work/project/requirements-other.txt'], self.read_state()['required'])
        self.assertEqual(2, self.audit().returncode)

    def test_project_bound_state_and_backend_approval_are_required(self):
        self.assertEqual(2, self.state('retire', self.file, '--deleted-by', self.deleted).returncode)
        path = self.root / '.version-sentinel/audit.json'
        state = self.read_state()
        state['root'] = str(self.repo)
        path.write_text(json.dumps(state))
        self.assert_blocked_unchanged()

    def wait_for_marker(self, path, timeout=10):
        deadline = time.monotonic() + timeout
        while not path.exists() and time.monotonic() < deadline:
            time.sleep(0.01)
        return path.exists()

    def paused_worker(self, label, arguments):
        marker = self.root / (label + '.read')
        release = self.root / (label + '.release')
        ready = self.root / (label + '.ready')
        worker = r"""
import importlib.util, json, pathlib, sys, time
script, marker, release, ready, arguments = sys.argv[1:]
sys.path.insert(0, str(pathlib.Path(script).parent))
spec = importlib.util.spec_from_file_location('project_state', script)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
original = module.read_json
def paused_read(path, default):
    data = original(path, default)
    if path.name == 'audit.json':
        pathlib.Path(marker).touch()
        deadline = time.monotonic() + 15
        while not pathlib.Path(release).exists():
            if time.monotonic() >= deadline:
                raise TimeoutError('test did not release paused audit read')
            time.sleep(0.01)
    return data
module.read_json = paused_read
sys.argv = [script, *json.loads(arguments)]
pathlib.Path(ready).touch()
module.main()
"""
        process = subprocess.Popen([sys.executable, '-c', worker,
            str(PLUGIN / 'scripts/lib/project-state.py'), str(marker), str(release),
            str(ready), json.dumps(arguments)], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        self.addCleanup(lambda: process.poll() is None and process.kill())
        self.assertTrue(self.wait_for_marker(ready), 'worker did not start')
        return process, marker, release

    def race_commands(self, second_arguments):
        first_arguments = ['retire', str(self.root), self.file, '--deleted-by', self.deleted,
                           '--user-confirmed', 'approved first deletion']
        first, marker, release = self.paused_worker('first', first_arguments)
        self.assertTrue(self.wait_for_marker(marker), 'first transaction did not read state')
        second, second_marker, second_release = self.paused_worker('second', second_arguments)
        # Force stale reads when no transaction lock exists. With a lock, the
        # second read cannot happen until the first transaction has committed.
        self.wait_for_marker(second_marker, timeout=0.5)
        release.touch()
        output, error = first.communicate(timeout=20)
        self.assertEqual(0, first.returncode, output + error)
        second_release.touch()
        output, error = second.communicate(timeout=20)
        self.assertEqual(0, second.returncode, output + error)

    def test_concurrent_retirements_keep_both_receipts_and_removals(self):
        other = self.repo / 'requirements-other.txt'
        other.write_text('')
        self.git('add', 'requirements-other.txt')
        self.git('commit', '-qm', 'second manifest')
        self.state('begin')
        self.git('rm', '-q', 'requirements-other.txt')
        self.git('commit', '-qm', 'second deliberate deletion')
        second_commit = self.git('rev-parse', 'HEAD').stdout.strip()
        self.race_commands(['retire', str(self.root), 'work/project/requirements-other.txt',
                            '--deleted-by', second_commit, '--user-confirmed', 'approved second deletion'])
        state = self.read_state()
        self.assertEqual(['work/project/package.json'], state['required'])
        self.assertEqual({self.file, 'work/project/requirements-other.txt'}, {r['file'] for r in state['retirements']})

    def test_concurrent_begin_preserves_retirement_receipt(self):
        self.race_commands(['begin', str(self.root)])
        state = self.read_state()
        self.assertEqual(['work/project/package.json'], state['required'])
        self.assertEqual([self.file], [r['file'] for r in state['retirements']])

    def test_recreated_deep_retired_include_is_audited_again(self):
        self.assertEqual(0, self.retire().returncode)
        deep = self.repo / 'a/b/c/d/requirements-old.txt'
        deep.parent.mkdir(parents=True)
        deep.write_text('')
        source = self.repo / 'requirements.txt'
        source.write_text('-r a/b/c/d/requirements-old.txt\n')
        self.git('add', '.')
        self.git('commit', '-qm', 'deep include')
        self.state('begin')
        source.write_text('')
        self.git('rm', '-q', 'a/b/c/d/requirements-old.txt')
        self.git('add', 'requirements.txt')
        self.git('commit', '-qm', 'retire deep include')
        commit = self.git('rev-parse', 'HEAD').stdout.strip()
        relative = 'work/project/a/b/c/d/requirements-old.txt'
        result = self.retire(relative, '--deleted-by', commit, '--user-confirmed', 'approved deep deletion')
        self.assertEqual(0, result.returncode, result.stdout + result.stderr)
        deep.parent.mkdir(parents=True, exist_ok=True)
        deep.write_text('lodash==4.17.21\n')
        snapshot = self.state('begin')
        self.assertEqual(0, snapshot.returncode, snapshot.stdout + snapshot.stderr)
        self.assertIn(relative, json.loads(snapshot.stdout)['required'])
        deep.unlink()
        self.assertEqual(2, self.state('begin').returncode)

    def test_grafts_cannot_forge_deletion_ancestry(self):
        self.git('reset', '--hard', self.initial)
        self.git('rm', '-q', 'requirements-seed.txt')
        self.git('commit', '-qm', 'different deletion', '--date=2000-01-01T00:00:00Z')
        head = self.git('rev-parse', 'HEAD').stdout.strip()
        self.assertEqual(1, self.git('merge-base', '--is-ancestor', self.deleted, head, check=False).returncode)
        graft = Path(self.git('rev-parse', '--git-path', 'info/grafts').stdout.strip())
        if not graft.is_absolute():
            graft = self.repo / graft
        graft.write_text(head + ' ' + self.deleted + '\n')
        self.assert_blocked_unchanged()

    def test_retirement_requires_real_repository(self):
        self.git('rev-parse', 'HEAD')
        # A deleted .git directory must not be accepted as Git evidence.
        (self.repo / '.git').rename(self.repo / 'git-backup')
        self.assert_blocked_unchanged()

unittest.main()
PY
