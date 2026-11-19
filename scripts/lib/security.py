#!/usr/bin/env python3
"""Read-only npm advisory checks and project-bound evidence (stdlib only).

An allowed result means no blocking *known* matching advisories within the
reported coverage. It does not establish package integrity or exploitability.
"""
import datetime as dt
import hashlib
import json
import math
import os
from pathlib import Path
import re
import secrets
import shutil
import subprocess
import sys
import tempfile
import urllib.error
import urllib.parse
import urllib.request

from path_helpers import resolve_path

EXCLUDED = {'.git', '.worktrees', 'node_modules', 'target', '.venv', 'venv', '.version-sentinel', '__pycache__'}
TRACKED = {'package.json', 'package-lock.json', 'npm-shrinkwrap.json', 'pnpm-lock.yaml', 'yarn.lock', 'bun.lock', 'bun.lockb', '.npmrc'}
SEVERITIES = {'info': 0, 'low': 1, 'moderate': 2, 'high': 3, 'critical': 4, 'unknown': 5}
EXACT = re.compile(r'^(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?$')
PACKAGE = re.compile(r'^(?:@[a-z0-9._~-]+/)?[a-z0-9._~-]+$')
LOCK_LOCATION = re.compile(r'^node_modules/(?:@[a-z0-9._~-]+/)?[a-z0-9._~-]+(?:/node_modules/(?:@[a-z0-9._~-]+/)?[a-z0-9._~-]+)*$')


class IncompleteScan(ValueError):
    """A failed provider can still have useful, reportable known findings."""
    def __init__(self, message, findings):
        super().__init__(message)
        self.findings = findings


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError(f'duplicate JSON key {key}')
        result[key] = value
    return result


def parse_json(raw):
    return json.loads(raw, object_pairs_hook=unique_object)


def object_value(value, label):
    if not isinstance(value, dict):
        raise ValueError(f'{label} is incomplete: expected object')
    return value


def list_value(value, label):
    if not isinstance(value, list):
        raise ValueError(f'{label} is incomplete: expected array')
    return value


def text_value(value, label):
    if not isinstance(value, str) or not value.strip():
        raise ValueError(f'{label} is incomplete: expected nonempty string')
    return value


def boolean(name):
    raw = os.environ.get('VS_' + name, os.environ.get('CLAUDE_PLUGIN_OPTION_' + name, 'true'))
    if raw.lower() in {'true', '1'}:
        return True
    if raw.lower() in {'false', '0'}:
        return False
    raise ValueError(f'Invalid {name}; use true/false or 1/0')


def settings():
    raw = os.environ.get('VS_WINDOW_HOURS', os.environ.get('CLAUDE_PLUGIN_OPTION_WINDOW_HOURS', '24'))
    window = float(raw)
    if not math.isfinite(window) or not 1 <= window <= 168:
        raise ValueError('Invalid freshness window; VS_WINDOW_HOURS must be 1 through 168 hours')
    return {'npm-audit': boolean('SECURITY_NPM_AUDIT'), 'osv': boolean('SECURITY_OSV'), 'window_hours': window,
            'block_level': 'high', 'unknown_severity': 'block', 'schema': 1}


def now():
    raw = os.environ.get('VS_NOW_OVERRIDE')
    return dt.datetime.strptime(raw, '%Y-%m-%dT%H:%M:%SZ').replace(tzinfo=dt.timezone.utc).timestamp() if raw else dt.datetime.now(dt.timezone.utc).timestamp()


def snapshot(root, config, contents=None):
    files = {}
    for directory, dirs, names in os.walk(root, followlinks=False):
        relative = Path(directory).relative_to(root)
        dirs[:] = [d for d in dirs if d not in EXCLUDED and len((relative / d).parts) < 4]
        for name in names:
            rel = relative / name
            if len(rel.parts) <= 4 and name in TRACKED:
                path = root / rel
                if path.is_symlink() or not path.is_file():
                    raise ValueError(f'incomplete security coverage: unsupported symlink/file {rel}')
                content = path.read_bytes()
                files[rel.as_posix()] = hashlib.sha256(content).hexdigest()
                if contents is not None:
                    contents[rel.as_posix()] = content
    return {'root': str(root), 'files': dict(sorted(files.items())), 'settings': config}


def state_path(root):
    return root / '.version-sentinel' / 'security.json'


def write_state(root, value):
    target = state_path(root)
    target.parent.mkdir(exist_ok=True)
    ignore = target.parent / '.gitignore'
    if not ignore.exists():
        ignore.write_text('*\n!.gitignore\n')
    descriptor, temporary = tempfile.mkstemp(prefix='.security-', dir=target.parent)
    try:
        with os.fdopen(descriptor, 'w', encoding='utf-8') as handle:
            json.dump(value, handle, sort_keys=True)
            handle.write('\n')
        os.replace(temporary, target)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def registry_selector(value):
    return isinstance(value, str) and not value.startswith(('file:', 'link:', 'workspace:', 'npm:', 'git', 'github:', 'http:', 'https:', './', '../', '/'))


def dependency_location(nodes, location, name):
    """Follow npm's nested-then-hoisted lookup without reading node_modules."""
    current = location
    while True:
        candidate = (current + '/' if current else '') + 'node_modules/' + name
        if candidate in nodes:
            return candidate
        if not current:
            return None
        current = current.rsplit('/node_modules/', 1)[0] if '/node_modules/' in current else ''


def locked_packages(root, manifest, proposed=None):
    """Return every registry node; unsupported provenance never disappears."""
    directory = manifest.parent
    path = directory / 'package-lock.json'
    if proposed is None and not path.is_file():
        raise ValueError(f'incomplete security coverage: missing package-lock.json for {manifest}')
    lock = object_value(parse_json(path.read_text(encoding='utf-8') if proposed is None else proposed), str(path))
    if type(lock.get('lockfileVersion')) is not int or lock['lockfileVersion'] not in (2, 3):
        raise ValueError(f'incomplete security coverage: {path} requires package-lock v2/v3')
    nodes = object_value(lock.get('packages'), 'lock packages')
    lock_root = object_value(nodes.get(''), 'lock root package')
    # A proposed lock may accompany a manifest change in the same tool call.
    # Check its own declared graph now; audit compares both files after writing.
    data = object_value(parse_json(manifest.read_text(encoding='utf-8')), str(manifest)) if proposed is None else lock_root
    if data.get('workspaces') or lock_root.get('workspaces'):
        raise ValueError(f'incomplete security coverage: workspaces unsupported in {manifest}')
    for other in ('npm-shrinkwrap.json', 'pnpm-lock.yaml', 'yarn.lock', 'bun.lock', 'bun.lockb'):
        if (directory / other).exists():
            raise ValueError(f'incomplete security coverage: unsupported lockfile {directory / other}; only package-lock.json v2/v3 supported')
    for kind in ('dependencies', 'devDependencies', 'optionalDependencies', 'peerDependencies'):
        declared = object_value(data.get(kind, {}), f'manifest {kind}')
        recorded = object_value(lock_root.get(kind, {}), f'lock {kind}')
        if declared != recorded:
            raise ValueError(f'incomplete security coverage: manifest and lock {kind} disagree in {manifest}')
        for name, selected in declared.items():
            if not PACKAGE.fullmatch(name) or not registry_selector(selected):
                raise ValueError(f'incomplete security coverage: unsupported dependency source {name}')
            # Peer packages can be absent when optional; absence is coverage unknown.
            if 'node_modules/' + name not in nodes:
                raise ValueError(f'incomplete security coverage: dependency {name} missing from lock packages')
    result = []
    for location, value in nodes.items():
        if location == '':
            continue
        entry = object_value(value, f'lock entry {location}')
        if not isinstance(location, str) or not LOCK_LOCATION.fullmatch(location) or any(part in {'.', '..'} for part in location.split('/')):
            raise ValueError(f'incomplete security coverage: unsupported package location {location}')
        inferred = location.rsplit('node_modules/', 1)[-1]
        name = entry.get('name', inferred)
        version = entry.get('version', '')
        resolved = entry.get('resolved', '')
        if (not isinstance(name, str) or not PACKAGE.fullmatch(name) or name != inferred or not isinstance(version, str)
                or not EXACT.fullmatch(version) or entry.get('link') or entry.get('inBundle')
                or not isinstance(resolved, str) or not resolved.startswith('https://') or not resolved.endswith('.tgz')):
            raise ValueError(f'incomplete security coverage: unsupported or missing registry metadata at {location}')
        expected = 'https://registry.npmjs.org/' + name + '/-/' + name.rsplit('/', 1)[-1] + '-' + version + '.tgz'
        if urllib.parse.unquote(resolved) != expected:
            raise ValueError(f'incomplete security coverage: only matching public npm registry tarballs supported at {location}')
        result.append({'name': name, 'version': version, 'node': location, 'project': manifest.parent.relative_to(root).as_posix()})
    for location, entry in nodes.items():
        for kind in ('dependencies', 'optionalDependencies', 'peerDependencies'):
            declared = object_value(entry.get(kind, {}), f'lock {location} {kind}')
            for name, selected in declared.items():
                if not PACKAGE.fullmatch(name) or not registry_selector(selected):
                    raise ValueError(f'incomplete security coverage: unsupported transitive dependency source {name} at {location}')
                if dependency_location(nodes, location, name) is None:
                    raise ValueError(f'incomplete security coverage: unresolved {kind} {name} at {location or "root"}')
    return result


def request_json(url, body=None):
    payload = json.dumps(body).encode('utf-8') if body is not None else None
    request = urllib.request.Request(url, data=payload, headers={'Content-Type': 'application/json', 'User-Agent': 'Version-Sentinel-security/1'})
    with urllib.request.urlopen(request, timeout=30) as response:
        # Avoid accepting arbitrarily large or truncated provider output.
        raw = response.read(16 * 1024 * 1024 + 1)
        if len(raw) > 16 * 1024 * 1024:
            raise ValueError('incomplete provider response: size limit exceeded')
        return object_value(parse_json(raw.decode('utf-8')), 'provider response')


def severity(value):
    normalized = value.lower() if isinstance(value, str) else ''
    if normalized == 'medium':
        normalized = 'moderate'
    return normalized if normalized in SEVERITIES else 'unknown'


def finding(provider, package, version, ids, level, links, affected, fixed, raw=None):
    return {'providers': [provider], 'package': package, 'versions': [version], 'ids': sorted(set(ids)),
            'severities': [level], 'links': sorted(set(links)), 'affected': affected, 'fixed': fixed,
            'details': [{'provider': provider, 'severity': level, 'raw_severity': raw}]}


def osv_findings(packages):
    findings = {}
    try:
        _osv_findings(packages, findings)
    except (ValueError, OSError, urllib.error.URLError, subprocess.SubprocessError) as error:
        raise IncompleteScan(str(error), list(findings.values())) from error
    return list(findings.values())


def _osv_findings(packages, findings):
    unique = sorted({(p['name'], p['version']) for p in packages})
    matches = {}
    for start in range(0, len(unique), 1000):
        pending = [(pair, None) for pair in unique[start:start + 1000]]
        seen_pages = set()
        pages = 0
        while pending:
            pages += 1
            if pages > 100:
                raise ValueError('incomplete OSV coverage: pagination limit exceeded')
            queries = []
            for (name, version), token in pending:
                query = {'package': {'ecosystem': 'npm', 'name': name}, 'version': version}
                if token:
                    query['page_token'] = token
                queries.append(query)
            response = request_json('https://api.osv.dev/v1/querybatch', {'queries': queries})
            if 'error' in response or 'code' in response:
                raise ValueError('incomplete OSV coverage: API error response')
            results = list_value(response.get('results'), 'OSV results')
            if len(results) != len(pending):
                raise ValueError('incomplete OSV coverage: batch result count mismatch')
            following = []
            for (pair, _), item in zip(pending, results):
                item = object_value(item, 'OSV batch item')
                if 'error' in item or 'code' in item or 'message' in item:
                    raise ValueError('incomplete OSV coverage: per-query API error')
                for short in list_value(item.get('vulns', []), 'OSV vulnerabilities'):
                    identifier = text_value(object_value(short, 'OSV vulnerability').get('id'), 'OSV ID')
                    matches.setdefault(identifier, set()).add(pair)
                    package, version = pair
                    findings[(identifier, package, version)] = finding('osv', package, version, [identifier], 'unknown',
                        ['https://osv.dev/vulnerability/' + urllib.parse.quote(identifier, safe='')], [], [], 'detail unavailable; scan incomplete')
                token = item.get('next_page_token')
                if token is not None:
                    text_value(token, 'OSV page token')
                    if (pair, token) in seen_pages:
                        raise ValueError('incomplete OSV coverage: repeated page token')
                    seen_pages.add((pair, token))
                    following.append((pair, token))
            pending = following
    for identifier, pairs in sorted(matches.items()):
        detail = request_json('https://api.osv.dev/v1/vulns/' + urllib.parse.quote(identifier, safe=''))
        if detail.get('id') != identifier or detail.get('withdrawn'):
            raise ValueError(f'incomplete OSV detail for {identifier}: mismatched or withdrawn record')
        aliases = list_value(detail.get('aliases', []), 'OSV aliases')
        ids = [identifier] + [text_value(a, 'OSV alias') for a in aliases]
        links = ['https://osv.dev/vulnerability/' + urllib.parse.quote(identifier, safe='')]
        for reference in list_value(detail.get('references', []), 'OSV references'):
            url = text_value(object_value(reference, 'OSV reference').get('url'), 'OSV reference URL')
            if url.startswith(('https://', 'http://')):
                links.append(url)
        affected = list_value(detail.get('affected'), 'OSV affected packages')
        for package, version in sorted(pairs):
            relevant = [object_value(a, 'OSV affected') for a in affected
                        if isinstance(a, dict) and isinstance(a.get('package'), dict)
                        and a['package'].get('ecosystem') == 'npm' and a['package'].get('name') == package]
            if not relevant:
                raise ValueError(f'incomplete OSV detail for {identifier}: missing matching npm package')
            raw = object_value(detail.get('database_specific', {}), 'OSV database metadata').get('severity')
            levels = [severity(raw)] if raw else []
            ranges, fixed = [], []
            for entry in relevant:
                for container in ('database_specific', 'ecosystem_specific'):
                    selected = object_value(entry.get(container, {}), f'OSV {container}').get('severity')
                    if selected:
                        levels.append(severity(selected))
                ranges.extend(list_value(entry.get('ranges', []), 'OSV affected ranges'))
                for item in list_value(entry.get('ranges', []), 'OSV affected ranges'):
                    for event in list_value(object_value(item, 'OSV range').get('events'), 'OSV range events'):
                        event = object_value(event, 'OSV range event')
                        if 'fixed' in event:
                            fixed.append(text_value(event['fixed'], 'OSV fixed version'))
                if 'versions' in entry:
                    ranges.append({'versions': list_value(entry['versions'], 'OSV affected versions')})
            level = max(levels, key=SEVERITIES.get) if levels else 'unknown'
            raw_severity = {'classification': raw, 'scores': detail.get('severity', [])}
            findings[(identifier, package, version)] = finding('osv', package, version, ids, level, links, ranges, sorted(set(fixed)), raw_severity)


def npm_findings(directory, packages):
    findings = []
    try:
        _npm_findings(directory, packages, findings)
    except (ValueError, OSError, subprocess.SubprocessError) as error:
        raise IncompleteScan(str(error), findings) from error
    return findings


def _npm_findings(directory, packages, results):
    executable = shutil.which('npm')
    if not executable:
        raise ValueError('incomplete npm-audit coverage: npm is unavailable')
    # Workspace filters are not supported by this scope; they must not reduce it.
    for key, value in os.environ.items():
        if key.lower() in {'npm_config_workspace', 'npm_config_workspaces'} and value:
            raise ValueError('incomplete npm-audit coverage: workspace configuration unsupported')
    npmrc = directory / '.npmrc'
    if npmrc.exists() and re.search(r'^\s*(?:workspace|workspaces)\s*=', npmrc.read_text(encoding='utf-8'), re.M | re.I):
        raise ValueError('incomplete npm-audit coverage: .npmrc workspace filters unsupported')
    args = [executable, 'audit', '--json', '--package-lock-only', '--ignore-scripts', '--audit-level=low',
            '--include=prod', '--include=dev', '--include=optional', '--include=peer', '--workspaces=false',
            '--prefix', str(directory)]
    response = subprocess.run(args, cwd=directory, capture_output=True, text=True, encoding='utf-8', timeout=90, check=False)
    if response.returncode not in (0, 1):
        raise ValueError(f'incomplete npm-audit coverage: npm exited {response.returncode}')
    report = object_value(parse_json(response.stdout), 'npm audit report')
    if report.get('error') or report.get('auditReportVersion') != 2:
        raise ValueError('incomplete npm-audit coverage: unsupported or failed audit report')
    metadata = object_value(report.get('metadata'), 'npm audit metadata')
    counts = object_value(metadata.get('vulnerabilities'), 'npm advisory counts')
    for key in ('info', 'low', 'moderate', 'high', 'critical', 'total'):
        if type(counts.get(key)) is not int or counts[key] < 0:
            raise ValueError('incomplete npm-audit coverage: invalid advisory counts')
    if sum(counts[key] for key in ('info', 'low', 'moderate', 'high', 'critical')) != counts['total']:
        raise ValueError('incomplete npm-audit coverage: inconsistent severity counts')
    count = object_value(metadata.get('dependencies'), 'npm dependency counts').get('total')
    if type(count) is not int or count < len(packages):
        raise ValueError('incomplete npm-audit coverage: resolved dependencies missing from report')
    vulnerabilities = object_value(report.get('vulnerabilities'), 'npm vulnerabilities')
    if bool(vulnerabilities) != bool(counts['total']) or (not vulnerabilities and response.returncode != 0):
        raise ValueError('incomplete npm-audit coverage: inconsistent findings/exit status')
    for name, item in vulnerabilities.items():
        item = object_value(item, 'npm advisory')
        nodes = list_value(item.get('nodes'), 'npm affected nodes')
        versions = sorted({p['version'] for p in packages if p['node'] in nodes})
        if not versions:
            raise ValueError(f'incomplete npm-audit coverage: unknown affected nodes for {name}')
        via = list_value(item.get('via'), 'npm advisory sources')
        for advisory in via:
            if isinstance(advisory, str):
                # npm meta-vulnerabilities are still blocking findings; retain them
                # separately when there is no direct advisory ID for this package.
                ids, links, level, affected = ['npm-meta:' + name + ':' + advisory], [], severity(item.get('severity')), item.get('range')
            else:
                advisory = object_value(advisory, 'npm advisory source')
                source = advisory.get('source')
                url = text_value(advisory.get('url'), 'npm advisory URL')
                ids = ['npm:' + str(source)] if isinstance(source, (int, str)) else []
                ids.extend(re.findall(r'(?:GHSA-[A-Za-z0-9-]+|CVE-\d{4}-\d+)', url))
                if not ids:
                    raise ValueError('incomplete npm-audit coverage: advisory ID unavailable')
                links, level, affected = [url], severity(advisory.get('severity')), advisory.get('range')
            fix = item.get('fixAvailable')
            fixed = [fix['version']] if isinstance(fix, dict) and isinstance(fix.get('version'), str) else []
            for version in versions:
                selected = finding('npm-audit', name, version, ids, level, links, [affected], fixed)
                selected['severities'] = sorted({level, severity(item.get('severity'))})
                selected['details'][0]['aggregate_severity'] = severity(item.get('severity'))
                results.append(selected)
        if not via:
            raise ValueError('incomplete npm-audit coverage: advisory has no source')
    # npm's metadata counts one vulnerability entry at its aggregate severity,
    # not one advisory source. Validate after parsing to retain all known IDs
    # if the provider's own severity summaries contradict each other.
    actual = {level: 0 for level in ('info', 'low', 'moderate', 'high', 'critical')}
    for item in vulnerabilities.values():
        level = severity(item.get('severity'))
        if level not in actual:
            raise ValueError('incomplete npm-audit coverage: missing aggregate severity')
        actual[level] += 1
        for source in item['via']:
            if isinstance(source, dict):
                source_level = severity(source.get('severity'))
                if source_level != 'unknown' and SEVERITIES[source_level] > SEVERITIES[level]:
                    raise ValueError('incomplete npm-audit coverage: advisory source severity exceeds aggregate severity')
    if any(actual[level] != counts[level] for level in actual) or len(vulnerabilities) != counts['total']:
        raise ValueError(f'incomplete npm-audit coverage: metadata severity counts {counts} contradict vulnerability entries')


def deduplicate(findings):
    result = []
    for current in findings:
        # Merge only identical package + alias-connected records. Keep every
        # provider severity, including unknown classifications, after merging.
        overlapping = [old for old in result if old['package'] == current['package'] and set(old['ids']).intersection(current['ids'])]
        for old in overlapping:
            result.remove(old)
            for key in ('providers', 'versions', 'ids', 'severities', 'links', 'fixed'):
                current[key] = sorted(set(current[key] + old[key]))
            current['affected'].extend(old['affected'])
            current['details'].extend(old['details'])
        result.append(current)
    return result


def blocked(findings):
    return any(any(level in {'high', 'critical', 'unknown'} for level in f['severities']) for f in findings)


def report(evidence):
    for provider, outcome in evidence.get('providers', {}).items():
        print(f'security {provider}: {outcome}')
    for gap in evidence.get('errors', []):
        print('security unknown/incomplete: ' + gap)
    for item in evidence.get('findings', []):
        print('security finding: ' + json.dumps(item, sort_keys=True))
    if evidence.get('status') == 'complete':
        print('security: no blocking known matching advisories within reported enabled-provider coverage; this is not proof of safety or exploitability.')
    elif evidence.get('status') == 'disabled':
        print('security: all advisory providers disabled; security coverage is disabled.')
    elif evidence.get('status') in {'blocked', 'incomplete'}:
        print('BLOCKED: version-sentinel. Security advisories or unknown/incomplete checks prevent dependency work.')


def audit(root, config):
    # Revoke prior evidence before parsing files or starting any provider.
    generation = secrets.token_hex(16)
    write_state(root, {'root': str(root), 'status': 'pending', 'generation': generation})
    # Hash and capture each input from the same read. Both providers must see
    # these bytes even if the live project changes A -> B -> A during a scan.
    inputs = {}
    before = snapshot(root, config, inputs)
    with tempfile.TemporaryDirectory(prefix='vs-security-scan-') as temporary:
        scan_root = Path(temporary)
        for name, content in inputs.items():
            destination = scan_root / name
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination.write_bytes(content)
        return audit_captured(root, scan_root, config, before, generation)


def audit_captured(root, scan_root, config, before, generation):
    manifests = [scan_root / name for name in before['files'] if Path(name).name == 'package.json']
    locks = [name for name in before['files'] if Path(name).name in TRACKED - {'package.json', '.npmrc'}]
    if not manifests and not locks:
        write_state(root, dict(before, generation=generation, checkedAt=now(), status='not-applicable'))
        return 0
    providers = {key: 'pending' if config[key] else 'disabled' for key in ('npm-audit', 'osv')}
    evidence = dict(before, generation=generation, checkedAt=now(), status='pending', providers=providers, findings=[], errors=[])
    if not any(config[p] for p in providers):
        evidence['status'] = 'disabled'
    else:
        packages = []
        projects = []
        for manifest in manifests:
            try:
                selected = locked_packages(scan_root, manifest)
                packages.extend(selected)
                projects.append((manifest.parent, selected))
            except (ValueError, OSError) as error:
                evidence['errors'].append(str(error))
        for lock in locks:
            if not (scan_root / lock).parent.joinpath('package.json').is_file():
                evidence['errors'].append(f'incomplete security coverage: lockfile without manifest: {lock}')
        # A failure in one provider does not prevent reports from the other.
        for provider in providers:
            if not config[provider]:
                continue
            try:
                if provider == 'osv':
                    evidence['findings'].extend(osv_findings(packages))
                else:
                    for directory, selected in projects:
                        evidence['findings'].extend(npm_findings(directory, selected))
                providers[provider] = 'complete' if not evidence['errors'] else 'incomplete'
            except (ValueError, OSError, urllib.error.URLError, subprocess.SubprocessError) as error:
                if isinstance(error, IncompleteScan):
                    evidence['findings'].extend(error.findings)
                providers[provider] = 'unknown/incomplete'
                evidence['errors'].append(f'{provider}: {error}')
        evidence['findings'] = deduplicate(evidence['findings'])
        evidence['status'] = 'incomplete' if evidence['errors'] else 'blocked' if blocked(evidence['findings']) else 'complete'
    # Evidence validation may fail after useful advisories were retrieved.
    # Keep those findings visible and, when this generation still owns state,
    # persist them as incomplete instead of losing them in a pending record.
    try:
        after = snapshot(root, config)
        frozen_after = snapshot(scan_root, config)
        if before != after or frozen_after['files'] != before['files']:
            evidence['errors'].append('incomplete security evidence: project or captured inputs changed during scan')
    except (ValueError, OSError) as error:
        evidence['errors'].append(f'incomplete security evidence: cannot verify scan inputs: {error}')
    try:
        current = object_value(parse_json(state_path(root).read_text(encoding='utf-8')), 'security state')
    except (ValueError, OSError) as error:
        current = {}
        evidence['errors'].append(f'incomplete security evidence: cannot verify audit generation: {error}')
    owns_state = current.get('generation') == generation
    if not owns_state:
        evidence['errors'].append('incomplete security evidence: another audit ran during scan; its state was preserved')
    if evidence['errors']:
        evidence['status'] = 'incomplete'
    if owns_state:
        try:
            write_state(root, evidence)
        except OSError as error:
            evidence['status'] = 'incomplete'
            evidence['errors'].append(f'incomplete security evidence: cannot save audit findings: {error}')
    report(evidence)
    return 0 if evidence['status'] in {'complete', 'disabled'} else 2


def gate(root, config):
    current = snapshot(root, config)
    path = state_path(root)
    if not current['files'] and not path.exists():
        return 0
    if not any(Path(name).name != '.npmrc' for name in current['files']) and not path.exists():
        return 0
    if not any(config[p] for p in ('npm-audit', 'osv')):
        print('security: all advisory providers disabled; security coverage is disabled.')
        return 0
    if not path.exists():
        raise ValueError('Security audit evidence missing; run bash scripts/check-versions.sh in this project')
    previous = object_value(parse_json(path.read_text(encoding='utf-8')), 'security evidence')
    if os.environ.get('VS_HOOK_LOCAL_ONLY') == '1' and previous.get('root') == str(root) and previous.get('findings'):
        print('security: cached advisory findings; run an explicit audit to refresh this report.')
        for item in previous['findings']:
            print('security finding: ' + json.dumps(item, sort_keys=True))
    age = now() - previous.get('checkedAt', 0)
    if previous.get('status') not in {'complete', 'not-applicable'} or not 0 <= age <= config['window_hours'] * 3600 or any(previous.get(key) != current[key] for key in current):
        raise ValueError('Security audit evidence missing, failed, expired, or project/settings changed; run bash scripts/check-versions.sh')
    return 0


def run(args):
    try:
        if len(args) < 2 or args[0] not in {'audit', 'gate', 'proposed', 'proposed-lock'}:
            raise ValueError('Usage: security-check.sh audit|gate ROOT; security-check.sh proposed ROOT PACKAGE VERSION; security-check.sh proposed-lock ROOT LOCKPATH < JSON')
        command, raw_root = args[:2]
        root = resolve_path(raw_root).resolve(strict=True)
        config = settings()
        if command == 'audit' and len(args) == 2:
            return audit(root, config)
        if command == 'gate' and len(args) == 2:
            return gate(root, config)
        if command == 'proposed-lock' and len(args) == 3:
            if not config['osv']:
                print('security osv: disabled; proposed-lock security coverage disabled. npm-audit covers only the currently resolved tree.')
                return 0
            path = resolve_path(args[2], root)
            relative = path.relative_to(root)
            if path.name != 'package-lock.json' or len(relative.parts) > 4 or EXCLUDED.intersection(relative.parts):
                raise ValueError('incomplete proposed lock coverage: only in-project package-lock.json v2/v3 supported')
            selected = locked_packages(root, path.parent / 'package.json', proposed=sys.stdin.read())
            found = deduplicate(osv_findings(selected))
            status = 'blocked' if blocked(found) else 'complete'
            report({'status': status, 'providers': {'osv': 'complete', 'npm-audit': 'resolved-tree only; not a proposed-lock check'}, 'findings': found})
            return 2 if status == 'blocked' else 0
        if command != 'proposed' or len(args) != 4:
            raise ValueError('Invalid security check arguments')
        package, version = args[2:]
        if not PACKAGE.fullmatch(package) or not EXACT.fullmatch(version):
            raise ValueError('Proposed npm security check requires a package name and exact semantic version')
        if not config['osv']:
            print('security osv: disabled; proposed-version security coverage disabled. npm-audit covers only the currently resolved tree.')
            return 0
        found = deduplicate(osv_findings([{'name': package, 'version': version}]))
        status = 'blocked' if blocked(found) else 'complete'
        report({'status': status, 'providers': {'osv': 'complete', 'npm-audit': 'resolved-tree only; not a proposed-version check'}, 'findings': found})
        return 2 if status == 'blocked' else 0
    except (ValueError, OSError, urllib.error.URLError, subprocess.SubprocessError, TypeError, KeyError) as error:
        if isinstance(error, IncompleteScan):
            report({'status': 'incomplete', 'providers': {'osv': 'unknown/incomplete'}, 'findings': deduplicate(error.findings)})
        print(f'BLOCKED: version-sentinel. Security unknown/incomplete: {error}', file=sys.stderr)
        return 2


if __name__ == '__main__':
    if hasattr(sys.stdout, 'reconfigure'):
        sys.stdout.reconfigure(encoding='utf-8', newline='\n')
    sys.exit(run(sys.argv[1:]))
