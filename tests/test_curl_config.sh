#!/usr/bin/env bash
# Exercise real curl: public registry lookups must not load ambient credentials.
set -u
VS_TEST_NAME="curl-config"
source "$(dirname "$0")/assert.sh"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VS_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$VS_TMPDIR"' EXIT

python3 - "$ROOT" "$VS_TMPDIR" <<'PY'
import os
from pathlib import Path
import subprocess
import sys
import threading
from http.server import BaseHTTPRequestHandler, HTTPServer

root, temporary = map(Path, sys.argv[1:])
requests = []


class Registry(BaseHTTPRequestHandler):
    def do_GET(self):
        requests.append(dict(self.headers.items()))
        body = b'{"version":"1.0.0"}'
        self.send_response(200)
        self.send_header("ETag", '"fixture-v1"')
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *args):
        pass


home = temporary / "home with spaces"
home.mkdir()
(home / ".curlrc").write_text(
    'header = "X-Ambient-Credential: fixture-only"\n'
    'user = "fixture-user:fixture-password"\n',
    encoding="utf-8",
)
environment = dict(os.environ, HOME=str(home), CURL_HOME=str(home),
                   XDG_CONFIG_HOME=str(home), VS_REQUIRE_ONLINE="1")
server = HTTPServer(("127.0.0.1", 0), Registry)
thread = threading.Thread(target=server.serve_forever, daemon=True)
thread.start()
url = f"http://127.0.0.1:{server.server_port}/package"

try:
    # The fixture deliberately enables HTTP only for this loopback request;
    # production registry requests remain restricted to HTTPS.
    command = 'source "$1/scripts/lib/etag-cache.sh"; curl_with_etag "$2" "$3" --proto =http --noproxy "*"'
    failures = []
    for bypass in ("0", "1"):
        environment["VS_ETAG_DISABLE"] = bypass
        result = subprocess.run(
            ["bash", "-c", command, "curl-config-test", root.as_posix(),
             (temporary / f"cache-{bypass}").as_posix(), url],
            env=environment, capture_output=True, text=True, timeout=10,
        )
        label = "uncached" if bypass == "1" else "cached"
        if result.returncode or result.stdout.strip() != '{"version":"1.0.0"}':
            failures.append(f"{label}: request failed: {result.stderr}")
            continue
        headers = {key.lower(): value for key, value in requests[-1].items()}
        if "authorization" in headers or "x-ambient-credential" in headers:
            failures.append(f"{label}: sent credentials from .curlrc")
    if failures:
        raise AssertionError("; ".join(failures))
    assert len(requests) == 2, "both curl paths must reach the local fixture"
finally:
    server.shutdown()
    server.server_close()
    thread.join()
PY
assert_exit_code 0 "$?" "both curl paths ignore the user's curl configuration"

finish_test
