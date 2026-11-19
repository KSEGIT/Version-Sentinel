"""Exercise security policy with captured provider responses; no network needed."""
import contextlib
import importlib.util
import io
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

LIB = Path(__file__).resolve().parents[1] / 'scripts' / 'lib'
sys.path.insert(0, str(LIB))


def load_engine():
    spec = importlib.util.spec_from_file_location('vs_security', LIB / 'security.py')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class SecurityEngineTests(unittest.TestCase):
    def setUp(self):
        self.env = patch.dict(os.environ, {}, clear=True)
        self.env.start()
        self.addCleanup(self.env.stop)
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)

    def engine(self):
        self.assertTrue((LIB / 'security.py').is_file(), 'security engine is missing')
        return load_engine()

    def project(self):
        (self.root / 'package.json').write_text(json.dumps({'name': 'fixture', 'dependencies': {'direct': '1.0.0'}}))
        data = {'name': 'fixture', 'lockfileVersion': 3, 'packages': {
            '': {'name': 'fixture', 'dependencies': {'direct': '1.0.0'}},
            'node_modules/direct': {'version': '1.0.0', 'resolved': 'https://registry.npmjs.org/direct/-/direct-1.0.0.tgz'},
            'node_modules/direct/node_modules/transitive': {'version': '2.0.0', 'resolved': 'https://registry.npmjs.org/transitive/-/transitive-2.0.0.tgz'},
        }}
        (self.root / 'package-lock.json').write_text(json.dumps(data))

    def command(self, module, *args):
        output = io.StringIO()
        with contextlib.redirect_stdout(output), contextlib.redirect_stderr(output):
            result = module.run(list(args))
        return result, output.getvalue()

    def clean_npm(self):
        return subprocess.CompletedProcess([], 0, json.dumps({'auditReportVersion': 2, 'vulnerabilities': {}, 'metadata': {'vulnerabilities': {'info': 0, 'low': 0, 'moderate': 0, 'high': 0, 'critical': 0, 'total': 0}, 'dependencies': {'total': 2}}}), '')

    def providers(self, module, request=None, npm=None):
        def default_request(url, body=None):
            return {'results': [{} for _ in body['queries']]}
        network = patch.object(module, 'request_json', side_effect=request or default_request)
        process = patch.object(module.subprocess, 'run', return_value=npm or self.clean_npm())
        executable = patch.object(module.shutil, 'which', return_value='/bin/npm')
        self.addCleanup(network.stop)
        self.addCleanup(process.stop)
        self.addCleanup(executable.stop)
        network.start()
        process.start()
        executable.start()

    def test_defaults_scan_transitive_and_preserve_fresh_evidence(self):
        self.project()
        module = self.engine()
        queried = []
        def request(url, body=None):
            queried.extend((q['package']['name'], q['version']) for q in body['queries'])
            return {'results': [{} for _ in body['queries']]}
        self.providers(module, request)
        code, out = self.command(module, 'audit', str(self.root))
        self.assertEqual(code, 0, out)
        self.assertIn(('transitive', '2.0.0'), queried)
        self.assertIn('npm-audit', out)
        self.assertIn('osv', out)
        self.assertEqual(self.command(module, 'gate', str(self.root))[0], 0)
        args = module.subprocess.run.call_args.args[0]
        self.assertIn('--include=dev', args)
        self.assertIn('--include=optional', args)
        self.assertIn('--include=peer', args)
        self.assertIn('--ignore-scripts', args)

    def test_missing_or_unsupported_lock_is_incomplete(self):
        self.project()
        module = self.engine()
        (self.root / 'package-lock.json').unlink()
        code, out = self.command(module, 'audit', str(self.root))
        self.assertEqual(code, 2)
        self.assertIn('incomplete', out)

    def test_each_provider_can_be_disabled_and_invalid_settings_block(self):
        self.project()
        module = self.engine()
        os.environ['VS_SECURITY_NPM_AUDIT'] = 'false'
        os.environ['VS_SECURITY_OSV'] = 'false'
        code, out = self.command(module, 'audit', str(self.root))
        self.assertEqual(code, 0, out)
        self.assertIn('disabled', out)
        self.assertNotIn('clean', out)
        os.environ['VS_SECURITY_OSV'] = 'maybe'
        self.assertEqual(self.command(module, 'audit', str(self.root))[0], 2)

    def test_provider_failures_and_partial_batches_cannot_authorize(self):
        self.project()
        module = self.engine()
        self.providers(module, lambda *args: {'results': []})
        self.assertEqual(self.command(module, 'audit', str(self.root))[0], 2)
        self.assertEqual(self.command(module, 'gate', str(self.root))[0], 2)

    def advisory(self, severity='HIGH'):
        return {'id': 'GHSA-fixture-1234', 'aliases': ['CVE-2026-1234'], 'database_specific': {'severity': severity},
                'references': [{'type': 'ADVISORY', 'url': 'https://github.com/advisories/GHSA-fixture-1234'}],
                'affected': [{'package': {'name': 'transitive', 'ecosystem': 'npm'},
                              'ranges': [{'type': 'SEMVER', 'events': [{'introduced': '0'}, {'fixed': '2.0.1'}]}]}]}

    def test_alias_dedup_keeps_both_providers_and_high_blocks(self):
        self.project()
        module = self.engine()
        report = self.clean_npm()
        parsed = json.loads(report.stdout)
        parsed['vulnerabilities'] = {'transitive': {'name': 'transitive', 'severity': 'high', 'range': '<2.0.1', 'nodes': ['node_modules/direct/node_modules/transitive'], 'via': [{'source': 1234, 'name': 'transitive', 'severity': 'high', 'url': 'https://github.com/advisories/GHSA-fixture-1234', 'range': '<2.0.1'}], 'fixAvailable': True}}
        parsed['metadata']['vulnerabilities'].update(high=1, total=1)
        report.stdout = json.dumps(parsed)
        def request(url, body=None):
            if body is not None:
                return {'results': [{'vulns': [{'id': 'GHSA-fixture-1234'}]} if q['package']['name'] == 'transitive' else {} for q in body['queries']]}
            return self.advisory()
        self.providers(module, request, report)
        code, out = self.command(module, 'audit', str(self.root))
        self.assertEqual(code, 2, out)
        evidence = json.loads((self.root / '.version-sentinel/security.json').read_text())
        self.assertEqual(len(evidence['findings']), 1)
        finding = evidence['findings'][0]
        self.assertEqual(set(finding['providers']), {'npm-audit', 'osv'})
        self.assertIn('CVE-2026-1234', finding['ids'])
        self.assertIn('2.0.1', out)
        self.assertEqual(self.command(module, 'gate', str(self.root))[0], 2)

    def test_unknown_severity_and_failed_details_block_proposed(self):
        module = self.engine()
        def request(url, body=None):
            return {'results': [{'vulns': [{'id': 'GHSA-fixture-1234'}]}]} if body is not None else self.advisory('')
        self.providers(module, request)
        code, out = self.command(module, 'proposed', str(self.root), 'transitive', '2.0.0')
        self.assertEqual(code, 2, out)
        self.assertIn('unknown', out)
        self.assertFalse((self.root / '.version-sentinel/security.json').exists())

    def test_pagination_fetches_later_vulnerabilities(self):
        module = self.engine()
        def request(url, body=None):
            if body is None:
                return self.advisory()
            query = body['queries'][0]
            return {'results': [{'vulns': [{'id': 'GHSA-fixture-1234'}]}]} if 'page_token' in query else {'results': [{'next_page_token': 'next'}]}
        self.providers(module, request)
        self.assertEqual(self.command(module, 'proposed', str(self.root), 'transitive', '2.0.0')[0], 2)

    def test_evidence_invalidates_on_time_files_settings_and_project(self):
        self.project()
        module = self.engine()
        self.providers(module)
        self.assertEqual(self.command(module, 'audit', str(self.root))[0], 0)
        path = self.root / '.version-sentinel/security.json'
        original = path.read_text()
        evidence = json.loads(original)
        evidence['checkedAt'] = 0
        path.write_text(json.dumps(evidence))
        self.assertEqual(self.command(module, 'gate', str(self.root))[0], 2)
        path.write_text(original)
        os.environ['VS_SECURITY_OSV'] = 'false'
        self.assertEqual(self.command(module, 'gate', str(self.root))[0], 2)
        del os.environ['VS_SECURITY_OSV']
        (self.root / 'package.json').write_text('{"dependencies":{}}')
        self.assertEqual(self.command(module, 'gate', str(self.root))[0], 2)

    def test_invalid_npm_output_and_exit_cannot_claim_clean(self):
        self.project()
        module = self.engine()
        self.providers(module, npm=subprocess.CompletedProcess([], 1, '{}', 'failure'))
        code, out = self.command(module, 'audit', str(self.root))
        self.assertEqual(code, 2, out)
        self.assertIn('incomplete', out)

    def test_local_sources_and_workspace_links_report_coverage_gap(self):
        self.project()
        module = self.engine()
        lock = self.root / 'package-lock.json'
        data = json.loads(lock.read_text())
        data['packages']['node_modules/direct']['resolved'] = 'file:../direct'
        lock.write_text(json.dumps(data))
        self.assertEqual(self.command(module, 'audit', str(self.root))[0], 2)

    def test_non_npm_project_needs_no_security_evidence(self):
        module = self.engine()
        (self.root / 'requirements.txt').write_text('requests==2.32.0\n')
        self.assertEqual(self.command(module, 'audit', str(self.root))[0], 0)
        self.assertEqual(self.command(module, 'gate', str(self.root))[0], 0)

    def test_provider_toggles_do_not_disable_the_other_provider(self):
        self.project()
        module = self.engine()
        self.providers(module)
        os.environ['VS_SECURITY_NPM_AUDIT'] = 'false'
        code, out = self.command(module, 'audit', str(self.root))
        self.assertEqual(code, 0, out)
        self.assertIn('npm-audit: disabled', out)
        self.assertIn('osv: complete', out)
        self.assertFalse(module.subprocess.run.called)
        os.environ['VS_SECURITY_NPM_AUDIT'] = 'true'
        os.environ['VS_SECURITY_OSV'] = 'false'
        code, out = self.command(module, 'audit', str(self.root))
        self.assertEqual(code, 0, out)
        self.assertIn('npm-audit: complete', out)
        self.assertIn('osv: disabled', out)

    def test_plugin_defaults_and_env_precedence_are_effective(self):
        self.project()
        module = self.engine()
        for name in ('plugin.json', '.claude-plugin/plugin.json'):
            manifest = json.loads((LIB.parents[1] / name).read_text())
            self.assertIs(manifest['userConfig']['security_osv']['default'], True)
            self.assertIs(manifest['userConfig']['security_npm_audit']['default'], True)
        os.environ['CLAUDE_PLUGIN_OPTION_SECURITY_NPM_AUDIT'] = 'false'
        os.environ['CLAUDE_PLUGIN_OPTION_SECURITY_OSV'] = 'false'
        self.assertEqual(self.command(module, 'audit', str(self.root))[0], 0)
        os.environ['VS_SECURITY_OSV'] = 'true'
        self.providers(module, lambda *args: {'results': []})
        self.assertEqual(self.command(module, 'audit', str(self.root))[0], 2)

    def test_root_binding_future_timestamp_and_scan_races_block(self):
        self.project()
        module = self.engine()
        self.providers(module)
        self.assertEqual(self.command(module, 'audit', str(self.root))[0], 0)
        path = self.root / '.version-sentinel/security.json'
        evidence = json.loads(path.read_text())
        evidence['root'] = '/a/different/project'
        path.write_text(json.dumps(evidence))
        self.assertEqual(self.command(module, 'gate', str(self.root))[0], 2)
        evidence['root'] = str(self.root)
        evidence['checkedAt'] = 99999999999
        path.write_text(json.dumps(evidence))
        self.assertEqual(self.command(module, 'gate', str(self.root))[0], 2)
        def change_during_scan(url, body=None):
            (self.root / 'package.json').write_text('{"dependencies":{}}')
            return {'results': [{} for _ in body['queries']]}
        module.request_json.side_effect = change_during_scan
        self.assertEqual(self.command(module, 'audit', str(self.root))[0], 2)
        self.assertEqual(self.command(module, 'gate', str(self.root))[0], 2)

    def test_unknown_osv_severity_survives_low_npm_alias_merge(self):
        module = self.engine()
        # Removing unknown classification during alias merge would authorize this.
        low = {'providers': ['npm-audit'], 'package': 'a', 'versions': ['1.0.0'], 'ids': ['GHSA-test'], 'severities': ['low'], 'links': [], 'affected': [], 'fixed': [], 'details': []}
        unknown = dict(low, providers=['osv'], severities=['unknown'])
        merged = module.deduplicate([low, unknown])
        self.assertTrue(module.blocked(merged))
        self.assertEqual(set(merged[0]['severities']), {'low', 'unknown'})

    def test_npm_workspace_filter_cannot_authorize_subset(self):
        self.project()
        module = self.engine()
        self.providers(module)
        (self.root / '.npmrc').write_text('workspace=only-one\n')
        code, out = self.command(module, 'audit', str(self.root))
        self.assertEqual(code, 2, out)
        self.assertIn('workspace', out)

    def test_deleted_all_npm_manifests_invalidates_prior_gate(self):
        self.project()
        module = self.engine()
        self.providers(module)
        self.assertEqual(self.command(module, 'audit', str(self.root))[0], 0)
        (self.root / 'package-lock.json').unlink()
        (self.root / 'package.json').unlink()
        self.assertEqual(self.command(module, 'gate', str(self.root))[0], 2)

    def test_osv_per_query_error_is_not_an_empty_clean_result(self):
        module = self.engine()
        self.providers(module, lambda *args: {'results': [{'error': 'unsupported query'}]})
        self.assertEqual(self.command(module, 'proposed', str(self.root), 'direct', '1.0.0')[0], 2)

    def test_malformed_lock_location_cannot_hide_behind_entry_name(self):
        self.project()
        module = self.engine()
        os.environ['VS_SECURITY_NPM_AUDIT'] = 'false'
        self.providers(module)
        lock = self.root / 'package-lock.json'
        data = json.loads(lock.read_text())
        data['packages']['node_modules/../outside'] = {'name': 'direct', 'version': '1.0.0', 'resolved': 'https://registry.npmjs.org/direct/-/direct-1.0.0.tgz'}
        lock.write_text(json.dumps(data))
        self.assertEqual(self.command(module, 'audit', str(self.root))[0], 2)

    def test_inconsistent_npm_severity_counts_are_incomplete(self):
        self.project()
        module = self.engine()
        report = self.clean_npm()
        data = json.loads(report.stdout)
        data['metadata']['vulnerabilities']['high'] = 1
        report.stdout = json.dumps(data)
        self.providers(module, npm=report)
        self.assertEqual(self.command(module, 'audit', str(self.root))[0], 2)

    def test_npm_aggregate_high_cannot_be_downgraded_by_low_source(self):
        self.project()
        module = self.engine()
        report = self.clean_npm()
        data = json.loads(report.stdout)
        data['metadata']['vulnerabilities'].update(high=1, total=1)
        data['vulnerabilities'] = {'transitive': {'name': 'transitive', 'severity': 'high', 'range': '<2.0.1', 'nodes': ['node_modules/direct/node_modules/transitive'], 'via': [{'source': 1234, 'severity': 'low', 'url': 'https://github.com/advisories/GHSA-fixture-1234', 'range': '<2.0.1'}], 'fixAvailable': True}}
        report.stdout = json.dumps(data)
        self.providers(module, npm=report)
        self.assertEqual(self.command(module, 'audit', str(self.root))[0], 2)

    def test_proposed_lock_checks_exact_transitive_versions_before_write(self):
        self.project()
        module = self.engine()
        def request(url, body=None):
            if body is None:
                return self.advisory()
            return {'results': [{'vulns': [{'id': 'GHSA-fixture-1234'}]} if q['package']['name'] == 'transitive' else {} for q in body['queries']]}
        self.providers(module, request)
        content = (self.root / 'package-lock.json').read_text()
        with patch.object(sys, 'stdin', io.StringIO(content)):
            code, out = self.command(module, 'proposed-lock', str(self.root), str(self.root / 'package-lock.json'))
        self.assertEqual(code, 2, out)
        self.assertIn('GHSA-fixture-1234', out)
        self.assertFalse((self.root / '.version-sentinel/security.json').exists())

    def test_proposed_lock_accepts_clean_and_rejects_malformed_json(self):
        self.project()
        module = self.engine()
        self.providers(module)
        content = (self.root / 'package-lock.json').read_text()
        with patch.object(sys, 'stdin', io.StringIO(content)):
            self.assertEqual(self.command(module, 'proposed-lock', str(self.root), 'package-lock.json')[0], 0)
        with patch.object(sys, 'stdin', io.StringIO('{')):
            self.assertEqual(self.command(module, 'proposed-lock', str(self.root), 'package-lock.json')[0], 2)
        self.assertFalse((self.root / '.version-sentinel/security.json').exists())

    def test_proposed_unsupported_lock_allows_explicit_osv_optout(self):
        module = self.engine()
        os.environ['VS_SECURITY_OSV'] = 'false'
        with patch.object(sys, 'stdin', io.StringIO('unsupported text')):
            code, out = self.command(module, 'proposed-lock', str(self.root), 'yarn.lock')
        self.assertEqual(code, 0, out)
        self.assertIn('disabled', out)

    def test_partial_osv_details_preserve_known_ids_and_findings(self):
        self.project()
        module = self.engine()
        def request(url, body=None):
            if body is not None:
                return {'results': [{'vulns': [{'id': 'GHSA-fixture-1234'}, {'id': 'GHSA-second-5678'}]} if q['package']['name'] == 'transitive' else {} for q in body['queries']]}
            if url.endswith('GHSA-fixture-1234'):
                return self.advisory()
            raise ValueError('failed to retrieve second detail')
        self.providers(module, request)
        code, out = self.command(module, 'audit', str(self.root))
        self.assertEqual(code, 2, out)
        self.assertIn('GHSA-fixture-1234', out)
        self.assertIn('GHSA-second-5678', out)
        evidence = json.loads((self.root / '.version-sentinel/security.json').read_text())
        self.assertEqual(len(evidence['findings']), 2)
        self.assertEqual(evidence['status'], 'incomplete')

    def test_missing_transitive_node_is_incomplete_with_osv_only(self):
        self.project()
        module = self.engine()
        os.environ['VS_SECURITY_NPM_AUDIT'] = 'false'
        self.providers(module)
        lock = self.root / 'package-lock.json'
        data = json.loads(lock.read_text())
        data['packages']['node_modules/direct']['dependencies'] = {'missing-transitive': '2.0.0'}
        lock.write_text(json.dumps(data))
        code, out = self.command(module, 'audit', str(self.root))
        self.assertEqual(code, 2, out)
        self.assertIn('missing-transitive', out)
        with patch.object(sys, 'stdin', io.StringIO(lock.read_text())):
            self.assertEqual(self.command(module, 'proposed-lock', str(self.root), 'package-lock.json')[0], 2)

    def test_nested_and_hoisted_transitive_nodes_are_both_covered(self):
        self.project()
        module = self.engine()
        os.environ['VS_SECURITY_NPM_AUDIT'] = 'false'
        self.providers(module)
        lock = self.root / 'package-lock.json'
        data = json.loads(lock.read_text())
        data['packages']['node_modules/direct']['dependencies'] = {'transitive': '2.0.0'}
        data['packages']['node_modules/direct/node_modules/transitive']['peerDependencies'] = {'direct': '1.0.0'}
        lock.write_text(json.dumps(data))
        self.assertEqual(self.command(module, 'audit', str(self.root))[0], 0)
        data['packages']['node_modules/transitive'] = data['packages'].pop('node_modules/direct/node_modules/transitive')
        lock.write_text(json.dumps(data))
        self.assertEqual(self.command(module, 'audit', str(self.root))[0], 0)

    def test_lock_identity_cannot_override_installed_package_name(self):
        self.project()
        module = self.engine()
        os.environ['VS_SECURITY_NPM_AUDIT'] = 'false'
        self.providers(module)
        lock = self.root / 'package-lock.json'
        data = json.loads(lock.read_text())
        data['packages']['node_modules/direct']['name'] = 'innocent-package'
        lock.write_text(json.dumps(data))
        self.assertEqual(self.command(module, 'audit', str(self.root))[0], 2)

    def test_arbitrary_tarball_is_not_identified_as_public_npm_code(self):
        self.project()
        module = self.engine()
        os.environ['VS_SECURITY_NPM_AUDIT'] = 'false'
        self.providers(module)
        lock = self.root / 'package-lock.json'
        data = json.loads(lock.read_text())
        data['packages']['node_modules/direct']['resolved'] = 'https://github.com/unknown/code/archive/1.0.0.tgz'
        lock.write_text(json.dumps(data))
        self.assertEqual(self.command(module, 'audit', str(self.root))[0], 2)

    def test_partial_npm_report_keeps_earlier_findings_on_later_error(self):
        self.project()
        module = self.engine()
        os.environ['VS_SECURITY_OSV'] = 'false'
        report = self.clean_npm()
        data = json.loads(report.stdout)
        data['metadata']['vulnerabilities'].update(high=2, total=2)
        data['vulnerabilities'] = {
            'transitive': {'name': 'transitive', 'severity': 'high', 'range': '<2.0.1', 'nodes': ['node_modules/direct/node_modules/transitive'], 'via': [{'source': 1234, 'severity': 'high', 'url': 'https://github.com/advisories/GHSA-fixture-1234', 'range': '<2.0.1'}], 'fixAvailable': True},
            'broken-second': {'severity': 'high', 'nodes': [], 'via': []},
        }
        report.stdout = json.dumps(data)
        self.providers(module, npm=report)
        code, out = self.command(module, 'audit', str(self.root))
        self.assertEqual(code, 2, out)
        self.assertIn('GHSA-fixture-1234', out)

    def test_metadata_high_cannot_disappear_into_low_entries_with_osv_disabled(self):
        self.project()
        module = self.engine()
        os.environ['VS_SECURITY_OSV'] = 'false'
        response = self.clean_npm()
        data = json.loads(response.stdout)
        data['metadata']['vulnerabilities'].update(high=1, total=1)
        data['vulnerabilities'] = {'direct': {
            'name': 'direct', 'severity': 'low', 'nodes': ['node_modules/direct'],
            'via': [{'source': 1234, 'severity': 'low',
                     'url': 'https://github.com/advisories/GHSA-fixture-1234', 'range': '*'}],
            'range': '*', 'fixAvailable': False}}
        response.stdout = json.dumps(data)
        self.providers(module, npm=response)
        code, out = self.command(module, 'audit', str(self.root))
        self.assertEqual(code, 2, out)
        evidence = json.loads((self.root / '.version-sentinel/security.json').read_text())
        self.assertEqual(evidence['status'], 'incomplete')
        self.assertIn('GHSA-fixture-1234', out)
        self.assertEqual(self.command(module, 'gate', str(self.root))[0], 2)

    def test_source_high_cannot_contradict_low_aggregate_severity(self):
        self.project()
        module = self.engine()
        os.environ['VS_SECURITY_OSV'] = 'false'
        response = self.clean_npm()
        data = json.loads(response.stdout)
        data['metadata']['vulnerabilities'].update(low=1, total=1)
        data['vulnerabilities'] = {'direct': {
            'name': 'direct', 'severity': 'low', 'nodes': ['node_modules/direct'],
            'via': [{'source': 1234, 'severity': 'high',
                     'url': 'https://github.com/advisories/GHSA-fixture-1234', 'range': '*'}],
            'range': '*', 'fixAvailable': False}}
        response.stdout = json.dumps(data)
        self.providers(module, npm=response)
        code, out = self.command(module, 'audit', str(self.root))
        self.assertEqual(code, 2, out)
        evidence = json.loads((self.root / '.version-sentinel/security.json').read_text())
        self.assertEqual(evidence['status'], 'incomplete')
        self.assertIn('GHSA-fixture-1234', out)

    def test_immutable_scan_inputs_survive_project_a_to_b_to_a_race(self):
        self.project()
        module = self.engine()
        original = {name: (self.root / name).read_bytes()
                    for name in ('package.json', 'package-lock.json')}
        alternate_manifest = json.loads(original['package.json'])
        alternate_manifest['dependencies']['direct'] = '2.0.0'
        alternate_lock = json.loads(original['package-lock.json'])
        alternate_lock['packages']['']['dependencies']['direct'] = '2.0.0'
        alternate_lock['packages']['node_modules/direct'].update(
            version='2.0.0', resolved='https://registry.npmjs.org/direct/-/direct-2.0.0.tgz')
        queried, npm_inputs = [], []
        def request(url, body=None):
            queried.extend((query['package']['name'], query['version']) for query in body['queries'])
            return {'results': [{} for _ in body['queries']]}
        self.providers(module, request)
        parse = module.locked_packages
        def mutate_before_parse(*args, **kwargs):
            (self.root / 'package.json').write_text(json.dumps(alternate_manifest))
            (self.root / 'package-lock.json').write_text(json.dumps(alternate_lock))
            return parse(*args, **kwargs)
        def run_npm(args, **kwargs):
            directory = Path(kwargs['cwd'])
            npm_inputs.append((directory, {name: (directory / name).read_bytes() for name in original}))
            for name, content in original.items():
                (self.root / name).write_bytes(content)
            return self.clean_npm()
        module.subprocess.run.side_effect = run_npm
        with patch.object(module, 'locked_packages', side_effect=mutate_before_parse):
            code, out = self.command(module, 'audit', str(self.root))
        self.assertEqual(code, 0, out)
        self.assertIn(('direct', '1.0.0'), queried)
        self.assertNotIn(('direct', '2.0.0'), queried)
        self.assertEqual(npm_inputs[0][1], original)
        self.assertNotEqual(npm_inputs[0][0], self.root)
        evidence = json.loads((self.root / '.version-sentinel/security.json').read_text())
        self.assertEqual(evidence['files']['package-lock.json'],
                         module.hashlib.sha256(original['package-lock.json']).hexdigest())
        self.assertEqual(self.command(module, 'gate', str(self.root))[0], 0)

    def test_captured_npm_config_and_inputs_are_checked_for_mutation(self):
        self.project()
        module = self.engine()
        original_config = b'registry=https://registry.npmjs.org/\n'
        (self.root / '.npmrc').write_bytes(original_config)
        self.providers(module)
        def run_npm(args, **kwargs):
            directory = Path(kwargs['cwd'])
            self.assertEqual((directory / '.npmrc').read_bytes(), original_config)
            self.assertEqual(args[args.index('--prefix') + 1], str(directory))
            (directory / 'package-lock.json').write_text('{}')
            return self.clean_npm()
        module.subprocess.run.side_effect = run_npm
        code, out = self.command(module, 'audit', str(self.root))
        self.assertEqual(code, 2, out)
        self.assertIn('changed', out)
        self.assertEqual(self.command(module, 'gate', str(self.root))[0], 2)

    def test_final_rejection_preserves_findings_without_clobbering_newer_audit(self):
        for change in ('captured', 'live', 'generation'):
            with self.subTest(change=change):
                self.project()
                module = self.engine()
                def request(url, body=None):
                    if body is None:
                        return self.advisory()
                    return {'results': [{'vulns': [{'id': 'GHSA-fixture-1234'}]}
                                        if q['package']['name'] == 'transitive' else {}
                                        for q in body['queries']]}
                self.providers(module, request)
                newer = {'generation': 'newer-audit', 'status': 'pending', 'marker': 'preserve'}
                def run_npm(args, **kwargs):
                    if change == 'generation':
                        (self.root / '.version-sentinel/security.json').write_text(json.dumps(newer))
                    else:
                        directory = Path(kwargs['cwd']) if change == 'captured' else self.root
                        (directory / 'package-lock.json').write_text('{}')
                    return self.clean_npm()
                module.subprocess.run.side_effect = run_npm
                code, out = self.command(module, 'audit', str(self.root))
                self.assertEqual(code, 2, out)
                self.assertIn('GHSA-fixture-1234', out)
                self.assertIn('high', out)
                self.assertIn('incomplete', out)
                saved = json.loads((self.root / '.version-sentinel/security.json').read_text())
                if change == 'generation':
                    self.assertEqual(saved, newer)
                else:
                    self.assertEqual(saved['status'], 'incomplete')
                    self.assertIn('GHSA-fixture-1234', saved['findings'][0]['ids'])
                self.assertEqual(self.command(module, 'gate', str(self.root))[0], 2)


if __name__ == '__main__':
    unittest.main()
