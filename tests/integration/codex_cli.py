#!/usr/bin/env python3
"""Run the real Codex CLI against a local, scripted Responses API.

No hosted model or credentials are used. The fixture supplies only model output;
Codex itself loads the plugin, dispatches apply_patch, and runs the real hooks.
"""
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
PATCH = '*** Begin Patch\n*** Update File: package.json\n@@\n-{"name":"cli-smoke","dependencies":{}}\n+{"name":"cli-smoke","dependencies":{"lodash":"4.17.21"}}\n*** End Patch'


class Fixture(BaseHTTPRequestHandler):
    def log_message(self, *_args):
        pass

    def do_POST(self):
        body = json.loads(self.rfile.read(int(self.headers['Content-Length'])))
        self.server.requests.append(body)
        if not self.path.endswith('/responses'):
            self.send_error(404)
            return
        turn = len(self.server.requests)
        if turn == 1:
            self.server.prepare(body['client_metadata']['session_id'])
            item = {'id': 'tool-1', 'type': 'custom_tool_call', 'status': 'completed',
                    'call_id': 'patch-1', 'name': 'apply_patch', 'input': PATCH}
        else:
            item = {'id': 'msg-1', 'type': 'message', 'role': 'assistant',
                    'status': 'completed', 'content': [{'type': 'output_text', 'text': 'Done.'}]}
        events = [
            {'type': 'response.created', 'response': {'id': f'resp-{turn}'}},
            {'type': 'response.output_item.done', 'output_index': 0, 'item': item},
            {'type': 'response.completed', 'response': {'id': f'resp-{turn}',
                'status': 'completed', 'output': [item],
                'usage': {'input_tokens': 1, 'output_tokens': 1, 'total_tokens': 2}}},
        ]
        data = ''.join(f'event: {event["type"]}\ndata: {json.dumps(event)}\n\n' for event in events).encode()
        self.send_response(200)
        self.send_header('Content-Type', 'text/event-stream')
        self.send_header('Content-Length', str(len(data)))
        self.end_headers()
        self.wfile.write(data)


def command(args, *, cwd, env, output, timeout=60):
    try:
        result = subprocess.run(args, cwd=cwd, env=env, input='', capture_output=True, text=True, timeout=timeout)
    except subprocess.TimeoutExpired as error:
        output.with_suffix('.stdout').write_bytes(error.stdout or b'')
        output.with_suffix('.stderr').write_bytes(error.stderr or b'')
        raise
    output.with_suffix('.stdout').write_text(result.stdout)
    output.with_suffix('.stderr').write_text(result.stderr)
    if result.returncode:
        raise AssertionError(f'{args[0]} failed ({result.returncode}); see {output}.stderr')
    return result


def run_case(base, name, enabled, recorded=False):
    case = base / name
    case.mkdir()
    home = case / 'codex-home'
    home.mkdir()
    project = case / 'project'
    project.mkdir()
    (project / 'package.json').write_text('{"name":"cli-smoke","dependencies":{}}\n')
    env = {key: os.environ[key] for key in ('PATH', 'SYSTEMROOT', 'WINDIR', 'TMPDIR', 'TEMP', 'TMP') if key in os.environ}
    env.update(HOME=str(home), USERPROFILE=str(home))
    env.update(VS_SESSION_ID=str(uuid.uuid4()), CODEX_HOME=str(home), OPENAI_API_KEY='local-fixture-not-a-real-key',
               VS_SECURITY_NPM_AUDIT='0', VS_SECURITY_OSV='0', VS_DISABLE='0',
               HTTP_PROXY='http://127.0.0.1:1', HTTPS_PROXY='http://127.0.0.1:1',
               ALL_PROXY='http://127.0.0.1:1', NO_PROXY='127.0.0.1,localhost')
    trace_dir = case
    shim_dir = case / 'bin'
    shim_dir.mkdir()
    # Observe only real public hooks. Forward stdin/output/status unchanged;
    # Codex exec JSON omits HookStarted/HookCompleted events.
    real_bash = shutil.which('bash')
    shim = shim_dir / 'bash'
    shim.write_text("#!/usr/bin/env python3\n" +
        "import json, os, pathlib, subprocess, sys, uuid\n" +
        "real = " + repr(real_bash) + "\n" +
        "script = pathlib.Path(sys.argv[1]).name if len(sys.argv) > 1 else ''\n" +
        "if script not in ('session-start.sh', 'detect-manifest-edit.sh', 'auto-record.sh'):\n" +
        "    os.execv(real, [real, *sys.argv[1:]])\n" +
        "payload = sys.stdin.buffer.read()\n" +
        "result = subprocess.run([real, *sys.argv[1:]], input=payload, capture_output=True)\n" +
        "path = pathlib.Path(" + repr(str(trace_dir)) + ") / ('hook-' + script + '-' + uuid.uuid4().hex + '.json')\n" +
        "path.write_text(json.dumps({'script': script, 'input': payload.decode(), 'stdout': result.stdout.decode(), 'stderr': result.stderr.decode(), 'returncode': result.returncode}))\n" +
        "sys.stdout.buffer.write(result.stdout)\n" +
        "sys.stderr.buffer.write(result.stderr)\n" +
        "sys.exit(result.returncode)\n")
    shim.chmod(0o755)
    env['PATH'] = str(shim_dir) + os.pathsep + env['PATH']
    env.update(http_proxy=env['HTTP_PROXY'], https_proxy=env['HTTPS_PROXY'], all_proxy=env['ALL_PROXY'], no_proxy=env['NO_PROXY'])
    server = ThreadingHTTPServer(('127.0.0.1', 0), Fixture)
    server.requests = []
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    catalog = home / 'models.json'
    catalog.write_text(json.dumps({'models': [{
        'slug': 'cli-fixture', 'display_name': 'Local fixture', 'description': 'No inference',
        'supported_reasoning_levels': [], 'shell_type': 'local', 'visibility': 'list',
        'supported_in_api': True, 'priority': 0, 'support_verbosity': False,
        'apply_patch_tool_type': 'freeform', 'truncation_policy': {'mode': 'bytes', 'limit': 10000},
        'experimental_supported_tools': [], 'base_instructions': 'Execute the supplied tool call.',
    }]}))
    (home / 'config.toml').write_text(f'''model = "cli-fixture"
model_catalog_json = {json.dumps(str(catalog))}
model_provider = "fixture"
[model_providers.fixture]
name = "Local integration fixture"
base_url = "http://127.0.0.1:{server.server_port}/v1"
wire_api = "responses"
supports_websockets = false
[features]
plugins = true
hooks = true
''')
    try:
        command(['bash', '-c', 'VS_TMPDIR="$2"; source "$1"; registry_fixture_setup',
                 'fixture', str(ROOT / 'tests/registry-fixture.sh'), str(case)],
                cwd=project, env=env, output=case / 'registry-setup')
        env['PATH'] = str(case / 'registry-bin') + os.pathsep + env['PATH']
        env.update(VS_ETAG_DISABLE='1', VS_REGISTRY_RETRIES='1')
        def prepare(session_id):
            env['VS_SESSION_ID'] = session_id
            command(['bash', str(ROOT / 'scripts/check-versions.sh')],
                    cwd=project, env=env, output=case / 'audit')
            if recorded:
                command(['bash', str(ROOT / 'scripts/vs-record.sh'), 'npm', 'lodash', '4.17.21',
                         'https://www.npmjs.com/package/lodash'], cwd=project, env=env, output=case / 'record')
            proposal = {'session_id': session_id, 'cwd': str(project), 'tool_name': 'apply_patch', 'tool_input': {'command': PATCH}}
            validation = subprocess.run(['bash', str(ROOT / 'scripts/validate-detect-manifest-edit.sh')],
                                        cwd=project, env={**env, 'VS_HOOK_LOCAL_ONLY': '1'},
                                        input=json.dumps(proposal), capture_output=True, text=True, timeout=15)
            (case / 'strict-validation.json').write_text(json.dumps({
                'returncode': validation.returncode, 'stdout': validation.stdout, 'stderr': validation.stderr}, indent=2))
            if recorded:
                assert validation.returncode == 0, f'{name}: recorded proposal did not validate'
            else:
                assert validation.returncode == 2, f'{name}: expected missing-record diagnostic'
                assert 'Package: lodash (npm). Version: 4.17.21.' in validation.stderr, f'{name}: wrong validation cause'
                assert 'No fresh successful online version check on record' in validation.stderr, f'{name}: wrong validation cause'
        server.prepare = prepare
        if enabled:
            command(['codex', 'plugin', 'marketplace', 'add', str(ROOT), '--json'],
                    cwd=project, env=env, output=case / 'marketplace')
            command(['codex', 'plugin', 'add', 'version-sentinel@version-sentinel-marketplace', '--json'],
                    cwd=project, env=env, output=case / 'install')
        result = command(['codex', 'exec', '--json', '--skip-git-repo-check',
                          '--trust', '--dangerously-bypass-hook-trust', '--sandbox', 'workspace-write',
                          'Add lodash version 4.17.21 to package.json using apply_patch.'],
                         cwd=project, env=env, output=case / 'cli')
    finally:
        server.shutdown()
        server.server_close()
        thread.join()
        (case / 'requests.json').write_text(json.dumps(server.requests, indent=2))
    assert len(server.requests) == 2, f'{name}: expected tool turn and completion'
    assert json.loads((project / 'package.json').read_text())['dependencies'] == {'lodash': '4.17.21'}, f'{name}: real edit did not execute'
    traces = [json.loads(path.read_text()) for path in trace_dir.glob('hook-*.json')]
    prehooks = [trace for trace in traces if trace['script'] == 'detect-manifest-edit.sh']
    assert len([trace for trace in traces if trace['script'] == 'auto-record.sh']) == int(enabled), f'{name}: expected post-edit hook invocation'
    assert len(prehooks) == int(enabled), f'{name}: expected exactly one real manifest hook invocation'
    warning = any('WARNING: Version Sentinel' in trace['stdout'] for trace in prehooks)
    assert all(trace['returncode'] == 0 for trace in traces), f'{name}: hook failed'
    assert warning == (enabled and not recorded), f'{name}: plugin warning presence {warning}, expected {enabled and not recorded}'
    print(f'{name}: real apply_patch succeeded; plugin warning={warning}')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output-dir', type=Path)
    args = parser.parse_args()
    if not shutil.which('codex'):
        parser.error('codex must be installed')
    output = args.output_dir or Path(tempfile.mkdtemp(prefix='vs-codex-cli-'))
    output = output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    print(f'Codex integration evidence: {output}', flush=True)
    run_case(output, 'without-plugin', False)
    run_case(output, 'with-plugin', True)
    run_case(output, 'recorded', True, recorded=True)


if __name__ == '__main__':
    main()
