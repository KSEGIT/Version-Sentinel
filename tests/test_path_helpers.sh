#!/usr/bin/env bash
VS_TEST_NAME=path-helpers
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
python3 - "$ROOT" <<'PY'
import importlib.util
from pathlib import Path, PureWindowsPath
import subprocess
import sys
import unittest
from unittest.mock import patch
sys.path.insert(0, str(Path(sys.argv[1]) / 'scripts' / 'lib'))
import path_helpers as paths
spec = importlib.util.spec_from_file_location('manifest_edit', Path(sys.argv[1]) / 'scripts' / 'lib' / 'manifest-edit.py')
manifest = importlib.util.module_from_spec(spec)
spec.loader.exec_module(manifest)

class PathBoundaries(unittest.TestCase):
    def test_windows_msys_json_path_uses_real_mount_mapping(self):
        def convert(args, **kwargs):
            if args != ['cygpath', '-C', 'UTF8', '-w', '--', '/tmp/project with spaces/package.json']:
                raise AssertionError(args)
            return subprocess.CompletedProcess(args, 0, 'C:\\Users\\runner\\Temp\\project with spaces\\package.json\r\n', '')
        with patch.object(paths.os, 'name', 'nt'), patch.object(paths.subprocess, 'run', convert):
            self.assertEqual('C:\\Users\\runner\\Temp\\project with spaces\\package.json', paths.native_path_text('/tmp/project with spaces/package.json'))

    def test_native_windows_path_is_not_reinterpreted(self):
        with patch.object(paths.os, 'name', 'nt'), patch.object(paths.subprocess, 'run', side_effect=AssertionError('must not remap native path')):
            self.assertEqual('C:/project/package.json', paths.native_path_text('C:/project/package.json'))
            self.assertEqual('C:\\project\\package.json', paths.native_path_text('C:\\project\\package.json'))
            self.assertEqual('relative/package.json', paths.native_path_text('relative/package.json'))

    def test_missing_mapper_cannot_guess_c_drive_tmp(self):
        with patch.object(paths.os, 'name', 'nt'), patch.object(paths.subprocess, 'run', side_effect=FileNotFoundError('cygpath')):
            with self.assertRaises(ValueError):
                paths.native_path_text('/tmp/project/package.json')

    def test_bash_script_argument_has_forward_separators(self):
        self.assertEqual('C:/plugin with spaces/scripts/audit-state.sh', paths.bash_script_path(PureWindowsPath('C:/plugin with spaces/scripts/audit-state.sh')))
        previous = manifest.SCRIPTS
        manifest.SCRIPTS = PureWindowsPath('C:/plugin with spaces/scripts')
        try:
            def invoke(args, **kwargs):
                self.assertEqual('C:/plugin with spaces/scripts/audit-state.sh', args[1])
                return subprocess.CompletedProcess(args, 0, '', '')
            with patch.object(manifest.subprocess, 'run', invoke):
                manifest.state('gate', Path.cwd(), Path.cwd())
        finally:
            manifest.SCRIPTS = previous

    def test_bash_launch_uses_the_path_resolved_executable(self):
        resolved = str(Path.cwd() / 'git with spaces' / 'bash.exe')
        def invoke(args, **kwargs):
            self.assertEqual(resolved, args[0])
            self.assertEqual(['audit-state.sh', 'validate-content', 'package.json'], args[1:])
            self.assertEqual('{}', kwargs['input'])
            return subprocess.CompletedProcess(args, 0, '', '')
        with patch.object(manifest.shutil, 'which', return_value=resolved), patch.object(manifest.subprocess, 'run', invoke):
            manifest.run(['bash', 'audit-state.sh', 'validate-content', 'package.json'], Path.cwd(), '{}')

    def test_missing_bash_blocks_before_process_launch(self):
        with patch.object(manifest.shutil, 'which', return_value=None), patch.object(manifest.subprocess, 'run', return_value=subprocess.CompletedProcess([], 0, '', '')):
            with self.assertRaises(manifest.Blocked):
                manifest.run(['bash', 'audit-state.sh'], Path.cwd())

    def test_windows_inventory_keys_use_forward_separators(self):
        self.assertEqual('nested/package.json', paths.relative_key(PureWindowsPath('C:/project/nested/package.json'), PureWindowsPath('C:/project')))

    def test_relative_paths_keep_project_boundary(self):
        root = Path.cwd().resolve()
        self.assertEqual(root / 'package.json', paths.resolve_path('package.json', root))
        self.assertNotEqual(root, paths.resolve_path('../outside', root))

unittest.main(argv=['path-helpers'])
PY
