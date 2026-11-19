"""One exact approved manifest transition may reconcile its existing npm lock.

This is not completed audit evidence and never permits a general install. The
explicit resolver stages its output, checks it, then replaces only that lock.
"""
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

from path_helpers import bash_script_path, resolve_path
import security

SCRIPTS = Path(__file__).resolve().parent.parent
FIELDS = ('dependencies', 'devDependencies', 'optionalDependencies', 'peerDependencies')


def load(name, filename):
    spec = importlib.util.spec_from_file_location(name, Path(__file__).parent / filename)
    value = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(value)
    return value


project = load('reconcile_project_state', 'project-state.py')


def config():
    # Match the shell entrypoint even when an explicit command is outside hooks.
    if os.environ.get('VS_HOOK_LOCAL_ONLY') != '1':
        load('reconcile_saved_settings', 'security-settings.py').apply_saved_settings()
    return security.settings()


def record_path(root):
    return root / '.version-sentinel' / 'reconcile.json'


def digest(raw):
    return hashlib.sha256(raw).hexdigest()


def authorize(root, proposed, eligible):
    """Called only after the ordinary gate and all candidate checks succeeded."""
    if not eligible:
        return
    if not any((manifest.parent / 'package-lock.json').is_file() for manifest, _, _ in eligible):
        return
    current_config = config()
    if not any(current_config[p] for p in ('npm-audit', 'osv')):
        return
    audit = project.read_json(project.state_path(root), {})
    evidence = project.read_json(security.state_path(root), {})
    current = project.inventory(root, audit)
    secured = security.snapshot(root, current_config)
    age = project.now() - evidence.get('checkedAt', 0)
    audit_age = project.now() - audit.get('checkedAt', 0)
    if (audit.get('status') != 'complete' or evidence.get('status') != 'complete'
            or any(audit.get(k) != current[k] for k in current)
            or any(evidence.get(k) != secured[k] for k in secured)
            or security.blocked(evidence.get('findings', []))
            or not 0 <= age <= current_config['window_hours'] * 3600
            or not 0 <= audit_age <= current_config['window_hours'] * 3600
            or any(evidence.get('providers', {}).get(p) != 'complete' for p in ('npm-audit', 'osv') if current_config[p])):
        raise ValueError('Current audited npm baseline changed while approving lock reconciliation; rerun the audit')
    locks = {}
    written_paths = {path for path, _, _ in proposed}
    for manifest, _, _ in eligible:
        lock = manifest.parent / 'package-lock.json'
        relative = lock.relative_to(root).as_posix()
        if lock not in written_paths and relative in secured['files'] and lock.is_file() and not lock.is_symlink():
            locks[relative] = manifest.relative_to(root).as_posix()
    if not locks:
        return
    if len(locks) != 1:
        raise ValueError('Edit and reconcile one npm project at a time before changing another npm manifest')
    for path, before, after in proposed:
        relative = path.relative_to(root).as_posix()
        if relative in current['files']:
            if before is None or digest(path.read_bytes()) != current['files'][relative]:
                raise ValueError('project changed while approving npm lock reconciliation')
            current['files'][relative] = digest(after.encode('utf-8'))
        if relative in secured['files']:
            secured['files'][relative] = digest(after.encode('utf-8'))
    project.write_json(record_path(root), {'root': str(root), 'checkedAt': min(audit['checkedAt'], evidence['checkedAt']),
        'settings': current_config, 'inventory': current, 'securityFiles': secured['files'],
        'locks': locks, 'session': os.environ.get('VS_SESSION_ID', '')})


def permit(root, lock):
    """Authorize only the unchanged old lock in the exact approved post-image."""
    root = root.resolve(strict=True)
    if lock.is_symlink():
        raise ValueError('symlink locks cannot be reconciled')
    lock = lock.resolve()
    relative = lock.relative_to(root).as_posix()
    record = project.read_json(record_path(root), {})
    selected = config()
    age = project.now() - record.get('checkedAt', 0)
    session = os.environ.get('VS_SESSION_ID', '')
    if (record.get('root') != str(root) or record.get('settings') != selected
            or not 0 <= age <= selected['window_hours'] * 3600
            or (session and record.get('session') != session)
            or relative not in record.get('locks', {}) or lock.name != 'package-lock.json'
            or lock.is_symlink() or not lock.is_file()
            or project.inventory(root, record['inventory']) != record['inventory']
            or security.snapshot(root, selected)['files'] != record.get('securityFiles')):
        raise ValueError('No current approved npm manifest transition; complete a normal audit before lock changes')
    manifest = root / record['locks'][relative]
    if manifest.parent != lock.parent:
        raise ValueError('invalid reconciliation manifest/lock pair')
    return record, manifest


def match_lock(root, lock, content):
    """A transition cannot introduce a different manifest through a lock root."""
    _, manifest = permit(root, lock)
    proposed = security.object_value(security.parse_json(content), 'proposed lock')
    nodes = security.object_value(proposed.get('packages'), 'proposed lock packages')
    declared = security.object_value(nodes.get(''), 'proposed lock root')
    current = security.object_value(security.parse_json(manifest.read_text(encoding='utf-8')), 'approved manifest')
    for key in (*FIELDS, 'workspaces'):
        if declared.get(key, {} if key in FIELDS else []) != current.get(key, {} if key in FIELDS else []):
            raise ValueError('proposed lock does not match the exact approved npm manifest')


def command(args, **kwargs):
    result = subprocess.run(args, capture_output=True, text=True, encoding='utf-8', timeout=180, check=False, **kwargs)
    if result.returncode:
        raise ValueError('\n'.join(p.strip() for p in (result.stdout, result.stderr) if p.strip()) or 'npm lock reconciliation failed')
    return result


def manifest_content(raw):
    """Allow npm serialization and its four empty dependency-table removals."""
    value = security.object_value(security.parse_json(raw.decode('utf-8')), 'staged manifest')
    # @npmcli/package-json prunes empty dependency tables when saving. Missing
    # and empty tables declare the same dependencies; no other fields are
    # normalized, and nonempty selectors must remain identical.
    for key in FIELDS:
        if type(value.get(key)) is dict and not value[key]:
            del value[key]
    # Canonical JSON keeps value types distinct (True must not equal 1), while
    # allowing whitespace, line-ending, escape and object-key-order changes.
    return json.dumps(value, sort_keys=True, ensure_ascii=False, separators=(',', ':'), allow_nan=False)


def regenerate(root, manifest):
    root = root.resolve(strict=True)
    manifest = resolve_path(str(manifest), root)
    lock = manifest.parent / 'package-lock.json'
    _, approved = permit(root, lock)
    if manifest != approved:
        raise ValueError('manifest was not approved for npm lock reconciliation')
    npm = shutil.which('npm')
    bash = shutil.which('bash')
    if not npm or not bash:
        raise ValueError('npm and bash are required for explicit npm lock reconciliation')
    inputs = {name: (manifest.parent / name).read_bytes() for name in ('package.json', 'package-lock.json')}
    npmrc = manifest.parent / '.npmrc'
    if npmrc.exists():
        inputs['.npmrc'] = npmrc.read_bytes()
    with tempfile.TemporaryDirectory(prefix='version-sentinel-reconcile-') as directory:
        staging = Path(directory)
        for name, raw in inputs.items():
            (staging / name).write_bytes(raw)
        # npm 10 treats an empty install as installing "." when localPrefix
        # equals globalTop, even with global=false. A CLI --prefix creates
        # that collision on Windows. Infer the local root from cwd instead;
        # an environment prefix affects only npm's separate global prefix.
        # Keep that unused prefix private and override every inherited casing.
        npm_environment = {key: value for key, value in os.environ.items()
                           if key.lower() != 'npm_config_prefix'}
        npm_environment['npm_config_prefix'] = str(staging / '.npm-global')
        # No caller-supplied flags, package names, scripts, audit fix or install
        # into node_modules. Only the staged lock can change.
        staged = command([npm, 'install', '--package-lock-only', '--ignore-scripts', '--no-audit', '--no-fund',
                 '--include=prod', '--include=dev', '--include=optional', '--include=peer',
                 '--workspaces=false', '--global=false', '--location=project'],
                 cwd=staging, env=npm_environment)
        sys.stdout.write(staged.stdout)
        sys.stderr.write(staged.stderr)
        # npm can serialize the temporary manifest while saving the lock.
        # Never copy that file back: the actual manifest stays byte-bound to
        # the approved transition. Only equivalent staged content is allowed.
        if manifest_content((staging / 'package.json').read_bytes()) != manifest_content(inputs['package.json']):
            raise ValueError('npm changed the approved staged manifest; lock not written')
        generated = (staging / 'package-lock.json').read_bytes()
        content = generated.decode('utf-8')
        match_lock(root, lock, content)
        proposed = command([bash, bash_script_path(SCRIPTS / 'security-check.sh'), 'proposed-lock', str(root), str(lock)],
                           cwd=root, input=content)
        sys.stdout.write(proposed.stdout)
        sys.stderr.write(proposed.stderr)
        # Revalidate all project/settings/time inputs after registry work. Both
        # providers will scan this exact post-image again before clean evidence.
        permit(root, lock)
        descriptor, temporary = tempfile.mkstemp(prefix='.reconciled-', dir=lock.parent)
        try:
            with os.fdopen(descriptor, 'wb') as handle:
                handle.write(generated)
            os.replace(temporary, lock)
        finally:
            if os.path.exists(temporary):
                os.unlink(temporary)
    record_path(root).unlink(missing_ok=True)
    completed = command([bash, bash_script_path(SCRIPTS / 'check-versions.sh')], cwd=root)
    if completed.stdout.strip():
        print(completed.stdout.strip())
    if completed.stderr.strip():
        print(completed.stderr.strip(), file=sys.stderr)
    print('version-sentinel: approved npm lock reconciled; full audit completed.')


if __name__ == '__main__':
    try:
        if len(sys.argv) != 3:
            raise ValueError('Usage: reconcile-npm-lock.sh PROJECT_ROOT PACKAGE_JSON')
        regenerate(resolve_path(sys.argv[1]), resolve_path(sys.argv[2], resolve_path(sys.argv[1])))
    except (ValueError, OSError, subprocess.SubprocessError, KeyError, TypeError) as error:
        print(f'BLOCKED: version-sentinel. {error}', file=sys.stderr)
        sys.exit(2)
