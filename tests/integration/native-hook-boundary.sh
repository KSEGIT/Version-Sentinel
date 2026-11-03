#!/usr/bin/env bash
# Fail early with the exact native Python -> Bash validation error.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
python3 - "$ROOT" <<'PY'
import importlib.util
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
root = Path(sys.argv[1])
sys.path.insert(0, str(root / 'scripts' / 'lib'))
spec = importlib.util.spec_from_file_location('manifest_edit', root / 'scripts' / 'lib' / 'manifest-edit.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
with tempfile.TemporaryDirectory() as directory:
    project = Path(directory)
    manifest = project / 'package.json'
    manifest.write_text('{}\n')
    result = module.state('validate-content', project, manifest, content='{}\n')
    if result.returncode:
        print('Python:', sys.executable)
        print('Bash on PATH:', shutil.which('bash'))
        print('Validation status:', result.returncode)
        print('Validation stdout:', result.stdout)
        print('Validation stderr:', result.stderr)
        bash = shutil.which('bash')
        if bash:
            control = subprocess.run([bash, (root / 'scripts' / 'audit-state.sh').as_posix(), 'validate-content', str(manifest)], cwd=project, input='{}\n', capture_output=True, text=True)
            print('Explicit PATH Bash status:', control.returncode)
            print('Explicit PATH Bash stderr:', control.stderr)
        raise SystemExit(1)
print('Native Python/Bash manifest validation passed')
PY
