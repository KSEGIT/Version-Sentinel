#!/usr/bin/env bash
VS_TEST_NAME=audit-crlf
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/tests/assert.sh"
VS_TMPDIR=$(mktemp -d)
trap 'rm -rf "$VS_TMPDIR"' EXIT
source "$ROOT/tests/registry-fixture.sh"
registry_fixture_setup
real_python=$(command -v python3)
mkdir -p "$VS_TMPDIR/python-bin" "$VS_TMPDIR/project"
printf '#!%s\n' "$real_python" > "$VS_TMPDIR/python-bin/python3"
cat >> "$VS_TMPDIR/python-bin/python3" <<'PY'
import os, subprocess, sys
p = subprocess.run([os.environ['VS_REAL_PYTHON'], *sys.argv[1:]], input=sys.stdin.buffer.read(), capture_output=True)
sys.stdout.buffer.write(p.stdout.replace(b'\n', b'\r\n'))
sys.stderr.buffer.write(p.stderr)
sys.exit(p.returncode)
PY
chmod +x "$VS_TMPDIR/python-bin/python3"
cd "$VS_TMPDIR/project" || exit 1
printf '%s\n' '{"dependencies":{"matching":"4.17.21","floating":"*"}}' > package.json
output=$(VS_REAL_PYTHON="$real_python" PATH="$VS_TMPDIR/python-bin:$PATH" bash "$ROOT/scripts/check-versions.sh" 2>&1); status=$?
assert_exit_code 0 "$status" "CRLF dependency output audit succeeds: $output"
row=$(printf '%s\n' "$output" | awk '$2 == "matching" {print $3, $4, $5}')
assert_eq '4.17.21 4.17.21 ok' "$row" 'matching version is not false drift'
row=$(printf '%s\n' "$output" | awk '$2 == "floating" {print $3, $4, $5}')
assert_eq '(unpinned) 4.17.21 UNPINNED' "$row" 'wildcard is reported as unpinned'
finish_test
