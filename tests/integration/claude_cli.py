#!/usr/bin/env python3
"""Run the real Claude CLI against a scripted, local Messages API."""
import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import threading
import uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

ROOT = Path(__file__).resolve().parents[2]


def run_case(output, enabled, recorded=False):
    name = 'recorded' if recorded else ('plugin' if enabled else 'control')
    case = output / name
    case.mkdir(parents=True)
    project = case / 'project'
    project.mkdir()
    manifest = project / 'package.json'
    manifest.write_text('{"name":"cli-fixture","dependencies":{}}\n')
    requests = []
    validations = []

    class Handler(BaseHTTPRequestHandler):
        def log_message(self, *_):
            pass

        def do_HEAD(self):
            self.send_response(200)
            self.end_headers()

        def do_POST(self):
            body = json.loads(self.rfile.read(int(self.headers['Content-Length'])))
            requests.append({'path': self.path, 'body': body})
            (case / 'requests.json').write_text(json.dumps(requests, indent=2))
            if self.path.split('?')[0] != '/v1/messages' or len(requests) > 10:
                self.send_response(404)
                self.end_headers()
                return
            # Auxiliary requests have no file tools; never consume a script step.
            names = {t.get('name') for t in body.get('tools', [])}
            history = json.dumps(body.get('messages', []))
            if 'Read' in names and 'toolu_fixture_read' not in history:
                content = {'type': 'tool_use', 'id': 'toolu_fixture_read', 'name': 'Read', 'input': {'file_path': str(manifest)}}
            elif 'Edit' in names and 'toolu_fixture_edit' not in history:
                content = {'type': 'tool_use', 'id': 'toolu_fixture_edit', 'name': 'Edit', 'input': {'file_path': str(manifest), 'old_string': '"dependencies":{}', 'new_string': '"dependencies":{"lodash":"4.17.21"}'}}
            else:
                content = {'type': 'text', 'text': 'Fixture complete.'}
            if content.get('name') == 'Edit':
                # The public advisory currently flattens multiline failures and
                # may show a security-provider summary instead of the package.
                # Check the same strict proposal before the real CLI executes it
                # so an unrelated validator error cannot make this test pass.
                payload = {'tool_name': 'Edit', 'tool_input': content['input'], 'cwd': str(project), 'session_id': session_id}
                validation = subprocess.run(['bash', str(ROOT / 'scripts/validate-detect-manifest-edit.sh')], cwd=project, env={**env, 'VS_HOOK_LOCAL_ONLY': '1'}, input=json.dumps(payload), capture_output=True, text=True, timeout=15)
                validations.append({'exit_code': validation.returncode, 'stdout': validation.stdout, 'stderr': validation.stderr})
                (case / 'strict-validation.json').write_text(json.dumps(validations, indent=2))
            stop = 'tool_use' if content['type'] == 'tool_use' else 'end_turn'
            msg = {'id': 'msg_fixture', 'type': 'message', 'role': 'assistant', 'model': body.get('model', 'fixture'), 'content': [content], 'stop_reason': stop, 'stop_sequence': None, 'usage': {'input_tokens': 1, 'output_tokens': 1}}
            self.send_response(200)
            self.send_header('Content-Type', 'text/event-stream' if body.get('stream') else 'application/json')
            self.end_headers()
            if not body.get('stream'):
                self.wfile.write(json.dumps(msg).encode())
                return
            def event(kind, data):
                self.wfile.write(('event: ' + kind + '\ndata: ' + json.dumps({'type': kind, **data}) + '\n\n').encode())
            event('message_start', {'message': {**msg, 'content': [], 'stop_reason': None, 'usage': {'input_tokens': 1, 'output_tokens': 0}}})
            if content['type'] == 'tool_use':
                event('content_block_start', {'index': 0, 'content_block': {**content, 'input': {}}})
                event('content_block_delta', {'index': 0, 'delta': {'type': 'input_json_delta', 'partial_json': json.dumps(content['input'])}})
            else:
                event('content_block_start', {'index': 0, 'content_block': {'type': 'text', 'text': ''}})
                event('content_block_delta', {'index': 0, 'delta': {'type': 'text_delta', 'text': content['text']}})
            event('content_block_stop', {'index': 0})
            event('message_delta', {'delta': {'stop_reason': stop, 'stop_sequence': None}, 'usage': {'output_tokens': 1}})
            event('message_stop', {})

    server = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    # Keep platform basics; never inherit provider credentials or routing flags.
    env = {k: v for k, v in os.environ.items() if k in {'PATH', 'HOME', 'TMPDIR', 'TMP', 'TEMP', 'LANG', 'LC_ALL', 'SYSTEMROOT', 'WINDIR'}}
    # A routing regression must fail rather than reach a hosted model endpoint.
    env.update({key: 'http://127.0.0.1:1' for key in ('HTTP_PROXY', 'HTTPS_PROXY', 'ALL_PROXY', 'http_proxy', 'https_proxy', 'all_proxy')})
    env.update({'NO_PROXY': '127.0.0.1,localhost', 'no_proxy': '127.0.0.1,localhost'})
    session_id = str(uuid.uuid4())
    (case / 'config').mkdir()
    env.update({'VS_SESSION_ID': session_id, 'ANTHROPIC_BASE_URL': f'http://127.0.0.1:{server.server_port}', 'ANTHROPIC_API_KEY': 'fixture-not-a-real-key', 'CLAUDE_CONFIG_DIR': str(case / 'config'), 'CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC': '1', 'CLAUDE_CODE_DISABLE_AUTO_MEMORY': '1', 'DISABLE_AUTOUPDATER': '1', 'VS_SECURITY_NPM_AUDIT': '0', 'VS_SECURITY_OSV': '0'})
    try:
        subprocess.run(['bash', '-c', 'VS_TMPDIR="$2"; source "$1"; registry_fixture_setup', 'fixture', str(ROOT / 'tests/registry-fixture.sh'), str(case)], check=True, env=env, timeout=15)
        env['PATH'] = str(case / 'registry-bin') + os.pathsep + env['PATH']
        env.update({'VS_ETAG_DISABLE': '1', 'VS_REGISTRY_RETRIES': '1'})
        setup_commands = [('check-versions.sh', [])]
        if recorded:
            setup_commands.append(('vs-record.sh', ['npm', 'lodash', '4.17.21', 'https://www.npmjs.com/package/lodash']))
        for script, arguments in setup_commands:
            setup = subprocess.run(['bash', str(ROOT / 'scripts' / script), *arguments], cwd=project, env=env, capture_output=True, text=True, timeout=30)
            (case / (script + '.log')).write_text(setup.stdout + setup.stderr)
            assert setup.returncode == 0, f'{name}: {script} failed; see {case}'
        command = ['claude', '-p', 'Read package.json then add lodash 4.17.21 using Edit.', '--session-id', session_id, '--output-format', 'stream-json', '--verbose', '--tools', 'Read,Edit', '--allowedTools', 'Read,Edit', '--setting-sources', '', '--strict-mcp-config', '--mcp-config', '{"mcpServers":{}}', '--no-session-persistence', '--debug-file', str(case / 'debug.log')]
        if enabled:
            command += ['--plugin-dir', str(ROOT)]
        result = subprocess.run(command, cwd=project, env=env, capture_output=True, text=True, timeout=90)
        (case / 'stdout.jsonl').write_text(result.stdout)
        (case / 'stderr.log').write_text(result.stderr)
    except subprocess.TimeoutExpired as error:
        (case / 'stdout.jsonl').write_bytes(error.stdout or b'')
        (case / 'stderr.log').write_bytes(error.stderr or b'')
        raise
    finally:
        server.shutdown()
        server.server_close()
        thread.join()
    assert result.returncode == 0, f'{name}: CLI exited {result.returncode}; see {case}'
    assert json.loads(manifest.read_text())['dependencies'] == {'lodash': '4.17.21'}, f'{name}: edit did not execute; see {case}'
    evidence = result.stdout + result.stderr + (case / 'debug.log').read_text()
    assert requests, f'{name}: no request reached local fixture; see {case}'
    events = [json.loads(line) for line in result.stdout.splitlines() if line.strip()]
    init = next(event for event in events if event.get('type') == 'system' and event.get('subtype') == 'init')
    assert not init.get('plugin_errors'), f'{name}: plugin load errors; see {case}'
    assert any(plugin['name'] == 'version-sentinel' for plugin in init.get('plugins', [])) == enabled, f'{name}: plugin registration mismatch; see {case}'
    assert len(validations) == 1, f'{name}: expected one strict edit validation; see {case}'
    validation = validations[0]
    diagnostics = validation['stderr']
    if recorded:
        assert validation['exit_code'] == 0, f'{name}: recorded proposal failed strict validation; see {case}'
    else:
        assert validation['exit_code'] == 2, f'{name}: missing record did not fail strict validation; see {case}'
        assert 'Package: lodash (npm). Version: 4.17.21.' in diagnostics, f'{name}: missing package-specific diagnostic; see {case}'
        assert 'No fresh successful online version check on record' in diagnostics, f'{name}: missing record was not the cause; see {case}'
        assert '---' not in diagnostics, f'{name}: unrelated validator failure; see {case}'
    warning = 'PreToolUse:Edit says: WARNING: Version Sentinel'
    assert (warning in result.stdout) == (enabled and not recorded), f'{name}: unexpected dependency warning evidence; see {case}'
    if enabled:
        assert 'PreToolUse:Edit' in evidence and 'detect-manifest-edit.sh' in evidence, f'{name}: no real edit hook evidence; see {case}'
        assert 'PostToolUse:Edit' in evidence and 'auto-record.sh' in evidence, f'{name}: no real post-edit hook evidence; see {case}'
    assert not any(event.get('is_error') for event in events if event.get('type') == 'result'), f'{name}: failed CLI result; see {case}'
    print(f'Claude {name}: real Edit executed; dependency warning {"present" if enabled and not recorded else "absent"}')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output-dir', type=Path)
    args = parser.parse_args()
    if not shutil.which('claude'):
        parser.error('claude CLI must be installed')
    output = (args.output_dir or Path(tempfile.mkdtemp(prefix='vs-claude-cli-'))).resolve()
    print(f'Evidence: {output}')
    run_case(output, False)
    run_case(output, True)
    run_case(output, True, recorded=True)


if __name__ == '__main__':
    main()
