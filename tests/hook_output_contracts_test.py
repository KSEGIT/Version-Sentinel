"""Host contracts catch root additionalContext rejected by Codex's strict parser."""
import json
import os
import pathlib
import shutil
import subprocess
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parent.parent
BASH = str(pathlib.Path(shutil.which('bash')).resolve())


def validate(value, schema, document, path='$'):
    """Check only the schema features reached by our emitted advisory objects."""
    if '$ref' in schema:
        target = document
        for part in schema['$ref'].removeprefix('#/').split('/'):
            target = target[part]
        validate(value, target, document, path)
    for child in schema.get('allOf', []):
        validate(value, child, document, path)
    types = {'object': dict, 'string': str, 'boolean': bool}
    if 'type' in schema:
        assert type(value) is types[schema['type']], f'{path}: wrong type'
    if 'const' in schema:
        assert value == schema['const'], f'{path}: wrong event'
    if 'enum' in schema:
        assert value in schema['enum'], f'{path}: invalid enum'
    if isinstance(value, dict):
        properties = schema.get('properties', {})
        if schema.get('additionalProperties') is False:
            assert not value.keys() - properties.keys(), f'{path}: unknown fields {value.keys() - properties.keys()}'
        assert not set(schema.get('required', [])) - value.keys(), f'{path}: missing required fields'
        for key, child in value.items():
            if key in properties:
                validate(child, properties[key], document, f'{path}.{key}')


class HookOutputContracts(unittest.TestCase):
    def test_public_hook_host_contracts(self):
        with tempfile.TemporaryDirectory() as directory:
            scripts = pathlib.Path(directory) / 'scripts'
            shutil.copytree(ROOT / 'scripts', scripts)
            # Isolate output transport from dependency checks and network providers.
            for name in ('detect-install-cmd', 'detect-manifest-edit', 'auto-record'):
                (scripts / f'validate-{name}.sh').write_bytes(
                    b'#!/usr/bin/env bash\nprintf \'security finding: quoted "advisory"\\nsecurity finding: second line\\n\' >&2\nexit 2\n')
            for name, event, fixture in (
                ('session-start', 'SessionStart', 'session-start'),
                ('detect-install-cmd', 'PreToolUse', 'pre-tool-use'),
                ('detect-manifest-edit', 'PreToolUse', 'pre-tool-use'),
                ('auto-record', 'PostToolUse', 'post-tool-use'),
            ):
                for mode in ('', '--gemini', '--copilot'):
                    with self.subTest(hook=name, mode=mode):
                        result = subprocess.run(
                            [BASH, (scripts / f'{name}.sh').as_posix(), mode],
                            input='invalid json', text=True, capture_output=True, cwd=directory, timeout=10,
                        )
                        self.assertEqual(result.returncode, 0, result.stderr)
                        self.assertEqual(result.stderr, '')
                        output = json.loads(result.stdout)
                        self.assertIn('Work may continue', output['systemMessage'])
                        if name != 'session-start':
                            self.assertIn('quoted "advisory"\nsecurity finding: second line', output['systemMessage'])
                        if mode == '--copilot':
                            self.assertIsInstance(output['additionalContext'], str)
                            self.assertEqual(output['hookSpecificOutput']['hookEventName'], event)
                            self.assertIn('Work may continue', output['hookSpecificOutput']['additionalContext'])
                        elif mode == '--gemini' and name != 'session-start':
                            self.assertEqual(set(output), {'systemMessage'})
                        else:
                            schema = json.loads((ROOT / 'tests/fixtures/codex-hook-output' / f'{fixture}.schema.json').read_text())
                            validate(output, schema, schema)
                            self.assertEqual(output['hookSpecificOutput']['hookEventName'], event)
                            self.assertIn('Work may continue', output['hookSpecificOutput']['additionalContext'])
                            self.assertEqual(set(output), {'systemMessage', 'hookSpecificOutput'})

    def test_missing_python_fallback_is_valid_codex_output(self):
        with tempfile.TemporaryDirectory() as directory:
            for name, fixture in (
                ('detect-install-cmd', 'pre-tool-use'),
                ('detect-manifest-edit', 'pre-tool-use'),
                ('auto-record', 'post-tool-use'),
            ):
                with self.subTest(hook=name):
                    result = subprocess.run(
                        [BASH, (ROOT / 'scripts' / f'{name}.sh').as_posix()],
                        input='{}', text=True, capture_output=True, cwd=directory,
                        env={**os.environ, 'PATH': directory}, timeout=10,
                    )
                    self.assertEqual(result.returncode, 0)
                    output = json.loads(result.stdout)
                    schema = json.loads((ROOT / 'tests/fixtures/codex-hook-output' / f'{fixture}.schema.json').read_text())
                    validate(output, schema, schema)
                    self.assertIn('Work may continue', output['systemMessage'])
                    self.assertEqual(set(output), {'systemMessage'})


if __name__ == '__main__':
    unittest.main()
