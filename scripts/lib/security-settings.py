#!/usr/bin/env python3
"""Resolve non-sensitive saved Claude provider options before security checks.

Hooks receive option environment variables. Standalone commands do not, so use
the documented CLI to read the exact installed plugin's configuration instead
of reading host settings or credential files directly.
"""
import json
import math
import os
from pathlib import Path
import re
import runpy
import shutil
import subprocess
import sys

OPTIONS = ('SECURITY_NPM_AUDIT', 'SECURITY_OSV')
PLUGIN_ID = re.compile(r'^version-sentinel@[A-Za-z0-9][A-Za-z0-9._-]*$')


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError('Cannot resolve saved Claude security settings: duplicate JSON keys')
        result[key] = value
    return result


def cli_json(executable, arguments):
    try:
        result = subprocess.run([executable, 'plugin', *arguments],
                                stdin=subprocess.DEVNULL, capture_output=True,
                                text=True, encoding='utf-8', timeout=10, check=False)
    except (OSError, subprocess.SubprocessError) as error:
        raise ValueError('Cannot resolve saved Claude security settings: CLI unavailable or timed out') from error
    if result.returncode:
        # CLI diagnostics may contain unrelated option data. Never repeat them.
        raise ValueError('Cannot resolve saved Claude security settings: CLI lookup failed or unsupported')
    try:
        return json.loads(result.stdout, object_pairs_hook=unique_object)
    except (ValueError, TypeError) as error:
        raise ValueError('Cannot resolve saved Claude security settings: invalid CLI response') from error


def saved_overrides(plugin_root=None, environment=None):
    environment = os.environ if environment is None else environment
    missing = [key for key in OPTIONS if 'VS_' + key not in environment
               and 'CLAUDE_PLUGIN_OPTION_' + key not in environment]
    if not missing:
        return {}
    executable = shutil.which('claude')
    if not executable:
        return {}
    plugin_root = Path(plugin_root or Path(__file__).resolve().parents[2]).resolve()
    listing = cli_json(str(Path(executable).resolve()), ['list', '--json'])
    if not isinstance(listing, list):
        raise ValueError('Cannot resolve saved Claude security settings: invalid plugin inventory')
    matches = []
    for item in listing:
        if not isinstance(item, dict):
            raise ValueError('Cannot resolve saved Claude security settings: invalid plugin inventory')
        location = item.get('readFromFolder', item.get('installPath'))
        if not isinstance(location, str) or not location or not Path(location).is_absolute():
            raise ValueError('Cannot resolve saved Claude security settings: invalid installation path')
        if Path(location).resolve() == plugin_root:
            matches.append(item)
    if not matches:
        # A checkout or CI script outside an installed Claude plugin has its own
        # explicit VS_* environment policy and retains the product defaults.
        return {}
    if len(matches) != 1:
        raise ValueError('Cannot resolve saved Claude security settings: ambiguous plugin installation')
    identifier = matches[0].get('id')
    if not isinstance(identifier, str) or not PLUGIN_ID.fullmatch(identifier):
        raise ValueError('Cannot resolve saved Claude security settings: unsupported plugin identity')
    result = cli_json(str(Path(executable).resolve()), ['configure', identifier, '--json'])
    if not isinstance(result, dict) or not isinstance(result.get('inputs'), dict):
        raise ValueError('Cannot resolve saved Claude security settings: invalid saved options')
    configured = result.get('configured', [])
    if not isinstance(configured, list) or any(not isinstance(key, str) for key in configured):
        raise ValueError('Cannot resolve saved Claude security settings: invalid configured options')
    overrides = {}
    for key in missing:
        name = key.lower()
        if name not in result['inputs']:
            if name in configured:
                raise ValueError('Cannot resolve saved Claude security settings: saved option unavailable')
            continue
        value = result['inputs'][name]
        if type(value) is bool:
            value = 'true' if value else 'false'
        if not isinstance(value, str) or value.lower() not in {'true', 'false', '1', '0'}:
            raise ValueError('Cannot resolve saved Claude security settings: invalid provider boolean')
        overrides['VS_' + key] = value.lower()
    # The same provider lookup can recover the saved freshness window so its
    # evidence policy agrees with hooks. Never launch the CLI for this alone.
    if 'VS_WINDOW_HOURS' not in environment and 'CLAUDE_PLUGIN_OPTION_WINDOW_HOURS' not in environment:
        if 'window_hours' in result['inputs']:
            value = result['inputs']['window_hours']
            try:
                window = float(value) if not isinstance(value, bool) else math.nan
            except (ValueError, TypeError, OverflowError):
                window = math.nan
            if not math.isfinite(window) or not 1 <= window <= 168:
                raise ValueError('Cannot resolve saved Claude security settings: invalid freshness window')
            overrides['VS_WINDOW_HOURS'] = str(window)
        elif 'window_hours' in configured:
            raise ValueError('Cannot resolve saved Claude security settings: saved freshness window unavailable')
    return overrides


def apply_saved_settings(plugin_root=None):
    """Fill absent policy values; callers can then use security.settings()."""
    os.environ.update(saved_overrides(plugin_root))


def main():
    try:
        engine = runpy.run_path(str(Path(__file__).with_name('security.py')),
                                run_name='security_settings_engine')
        arguments = sys.argv[1:]
        relevant = True
        if len(arguments) == 2 and arguments[0] in {'audit', 'gate'}:
            root = engine['resolve_path'](arguments[1]).resolve(strict=True)
            if arguments[0] == 'audit':
                # A requested rescan revokes old success even when inventory or
                # host option lookup fails before the provider engine starts.
                engine['write_state'](root, {'root': str(root), 'status': 'pending'})
            current = engine['snapshot'](root, {})
            relevant = any(Path(name).name in engine['TRACKED'] - {'.npmrc'}
                           for name in current['files'])
        if relevant:
            apply_saved_settings()
    except (ValueError, OSError, subprocess.SubprocessError) as error:
        print(f'BLOCKED: version-sentinel. Security unknown/incomplete: {error}', file=sys.stderr)
        return 2
    return engine['run'](arguments)


if __name__ == '__main__':
    if hasattr(sys.stdout, 'reconfigure'):
        sys.stdout.reconfigure(encoding='utf-8', newline='\n')
    sys.exit(main())
