#!/usr/bin/env bash
VS_TEST_NAME=path-helpers
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/tests/assert.sh"
python3 - "$ROOT" <<'PY'
import importlib.util
import io
import json
from pathlib import Path, PureWindowsPath
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch
sys.path.insert(0, str(Path(sys.argv[1]) / 'scripts' / 'lib'))
import path_helpers as paths
spec = importlib.util.spec_from_file_location('manifest_edit', Path(sys.argv[1]) / 'scripts' / 'lib' / 'manifest-edit.py')
manifest = importlib.util.module_from_spec(spec)
spec.loader.exec_module(manifest)
state_spec = importlib.util.spec_from_file_location('project_state', Path(sys.argv[1]) / 'scripts' / 'lib' / 'project-state.py')
state = importlib.util.module_from_spec(state_spec)
state_spec.loader.exec_module(state)

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

    def test_audit_root_argv_uses_native_path_mapping(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve()
            with patch.object(state, 'resolve_path', return_value=root) as mapper, patch.object(state.sys, 'argv', ['state', 'invalidate', "/tmp/project's directory"]):
                state.main()
            mapper.assert_called_once_with("/tmp/project's directory")
            self.assertEqual(str(root), json.loads((root / '.version-sentinel' / 'audit.json').read_text())['root'])

    def test_audit_manifest_argv_uses_native_path_mapping(self):
        with tempfile.TemporaryDirectory() as directory:
            manifest_path = Path(directory) / 'package.json'
            manifest_path.write_text('{"dependencies":{"lodash":"4.17.21"}}')
            output = io.StringIO()
            with patch.object(state, 'resolve_path', return_value=manifest_path) as mapper, patch.object(state.sys, 'argv', ['state', 'deps', "/tmp/project's directory/package.json"]), patch.object(state.sys, 'stdout', output):
                state.main()
            mapper.assert_called_once_with("/tmp/project's directory/package.json")
            self.assertEqual('lodash\t4.17.21\n', output.getvalue())

    def test_audit_explicit_target_uses_native_path_mapping(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve()
            target = root / 'package.json'
            with patch.object(state, 'resolve_path', return_value=target) as mapper:
                self.assertEqual((target, 'package.json'), state.usable_path(root, "/tmp/project's directory/package.json"))
            mapper.assert_called_once_with("/tmp/project's directory/package.json", root)

unittest.main(argv=['path-helpers'])
PY
assert_exit_code 0 "$?" 'Python path boundary regression tests'

# A native Python entrypoint needs explicit mapping: MSYS argv conversion can
# leave apostrophe-containing /tmp paths untouched. Do not remap other argv.
VS_TMPDIR=$(mktemp -d)
trap 'rm -rf "$VS_TMPDIR"' EXIT
mkdir -p "$VS_TMPDIR/bin"
cat > "$VS_TMPDIR/bin/python3" <<'PYTHON'
#!/usr/bin/env bash
[[ "$1" == -c ]] && exit 0
printf '%s\n' "$1"
PYTHON
cat > "$VS_TMPDIR/bin/cygpath" <<'CYGPATH'
#!/usr/bin/env bash
[[ "${VS_TEST_MAPPING_FAILURE:-0}" == 1 ]] && exit 1
[[ "${VS_TEST_MAPPING_EMPTY:-0}" == 1 ]] && exit 0
printf '%s\r\n' "C:/native/plugin's directory/scripts/lib/project-state.py"
CYGPATH
chmod +x "$VS_TMPDIR/bin/python3" "$VS_TMPDIR/bin/cygpath"
output=$(PATH="$VS_TMPDIR/bin:$PATH" bash "$ROOT/scripts/audit-state.sh" invalidate "$VS_TMPDIR" 2>&1); status=$?
assert_exit_code 0 "$status" 'audit entrypoint can be mapped for native Python'
assert_eq "C:/native/plugin's directory/scripts/lib/project-state.py" "$output" 'audit invokes Python with mapped entrypoint and strips CRLF transport'
output=$(PATH="$VS_TMPDIR/bin:$PATH" VS_TEST_MAPPING_FAILURE=1 bash "$ROOT/scripts/audit-state.sh" invalidate "$VS_TMPDIR" 2>&1); status=$?
assert_exit_code 2 "$status" 'audit entrypoint mapping failure fails closed'
assert_contains "$output" 'BLOCKED: version-sentinel.' 'audit entrypoint mapping failure is explained'
output=$(PATH="$VS_TMPDIR/bin:$PATH" VS_TEST_MAPPING_EMPTY=1 bash "$ROOT/scripts/audit-state.sh" invalidate "$VS_TMPDIR" 2>&1); status=$?
assert_exit_code 2 "$status" 'empty audit entrypoint mapping fails closed'
assert_contains "$output" 'BLOCKED: version-sentinel.' 'empty audit entrypoint mapping is explained'

finish_test
