#!/usr/bin/env bash
# Exercise the public command against real temporary Git repositories.
set -eu
VS_RETIRE_TEST_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export VS_RETIRE_TEST_ROOT
python3 - <<'PY'
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

PLUGIN = Path(os.environ['VS_RETIRE_TEST_ROOT'])

class ManifestRetirement(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='vs-retirement-')
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.repo = self.root / 'work' / 'project'
        self.repo.mkdir(parents=True)
        self.file = 'work/project/requirements-seed.txt'
        self.target = self.root / self.file
        self.target.write_text('# deliberately retired\n')
        (self.repo / 'package.json').write_text('{"dependencies":{"lodash":"4.17.21"}}')
        self.git('init', '-q')
        self.git('config', 'user.email', 'fixture@example.invalid')
        self.git('config', 'user.name', 'Fixture')
        self.git('add', '.')
        self.git('commit', '-qm', 'initial')
        self.initial = self.git('rev-parse', 'HEAD').stdout.strip()
        self.state('begin')
        self.git('rm', '-q', 'requirements-seed.txt')
        self.git('commit', '-qm', 'deliberately retire seed requirements')
        self.deleted = self.git('rev-parse', 'HEAD').stdout.strip()

    def git(self, *args, check=True):
        return subprocess.run(['git', '-C', str(self.repo), *args], capture_output=True, text=True, check=check)

    def state(self, *args):
        return subprocess.run(['bash', str(PLUGIN / 'scripts/audit-state.sh'), args[0], str(self.root), *args[1:]], capture_output=True, text=True)

    def retire(self, *args):
        if not args:
            args = (self.file, '--deleted-by', self.deleted, '--user-confirmed', 'Daniel approved this committed deletion')
        return subprocess.run(['bash', str(PLUGIN / 'scripts/retire-manifest.sh'), *args], cwd=self.root, capture_output=True, text=True)

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
        curl.write_text('#!/usr/bin/env bash\n' + ('exit 7\n' if fail else 'printf \'%s\\n\' \'{"name":"lodash","dist-tags":{"latest":"4.17.21"},"versions":{"4.17.21":{}}}\'\n'))
        curl.chmod(0o755)
        env = dict(os.environ, PATH=str(bindir) + os.pathsep + os.environ['PATH'], VS_ETAG_DISABLE='1', VS_REGISTRY_RETRIES='1', VS_REGISTRY_RETRY_DELAY='0')
        return subprocess.run(['bash', str(PLUGIN / 'scripts/check-versions.sh')], cwd=self.root, env=env, capture_output=True, text=True)

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

    def test_retirement_requires_real_repository(self):
        self.git('rev-parse', 'HEAD')
        # A deleted .git directory must not be accepted as Git evidence.
        (self.repo / '.git').rename(self.repo / 'git-backup')
        self.assert_blocked_unchanged()

unittest.main()
PY
