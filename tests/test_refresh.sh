#!/usr/bin/env bash
# Refresh runs the real audit in the caller's project with fixture registry replies.
VS_TEST_NAME=refresh
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/tests/assert.sh"
source "$ROOT/tests/registry-fixture.sh"
VS_TMPDIR=$(mktemp -d)
trap 'rm -rf "$VS_TMPDIR"' EXIT
registry_fixture_setup
export VS_DISABLE=0 VS_NOW_OVERRIDE=2026-11-22T22:15:00Z
unset VS_WINDOW_HOURS CLAUDE_PLUGIN_OPTION_WINDOW_HOURS
unset VS_SESSION_ID CODEX_THREAD_ID

project="$VS_TMPDIR/project with spaces"
mkdir -p "$project"
cd "$project" || exit 1
manifest='{"dependencies":{"lodash":"4.17.20"}}'
printf '%s\n' "$manifest" > package.json
cat > package-lock.json <<'LOCK'
{"lockfileVersion":3,"packages":{"":{"dependencies":{"lodash":"4.17.20"}},"node_modules/lodash":{"version":"4.17.20","resolved":"https://registry.npmjs.org/lodash/-/lodash-4.17.20.tgz"}}}
LOCK
cat > "$VS_TMPDIR/registry-bin/npm" <<'NPM'
#!/usr/bin/env bash
[[ "$1" == audit ]] || exit 3
cat "${BASH_SOURCE[0]%/*}/npm-report.json"
exit 1
NPM
cat > "$VS_TMPDIR/registry-bin/npm.cmd" <<'NPM'
@echo off
if not "%1"=="audit" exit /b 3
type "%~dp0npm-report.json"
exit /b 1
NPM
cat > "$VS_TMPDIR/registry-bin/npm-report.json" <<'REPORT'
{"auditReportVersion":2,"vulnerabilities":{"lodash":{"severity":"low","via":[{"source":12345,"name":"lodash","severity":"low","range":"<4.17.21","url":"https://github.com/advisories/GHSA-fixture-low"}],"nodes":["node_modules/lodash"],"fixAvailable":{"version":"4.17.21"}}},"metadata":{"vulnerabilities":{"info":0,"low":1,"moderate":0,"high":0,"critical":0,"total":1},"dependencies":{"total":1}}}
REPORT
chmod +x "$VS_TMPDIR/registry-bin/npm"

output=$(VS_SECURITY_NPM_AUDIT=1 bash "$ROOT/scripts/vs-refresh.sh" 2>"$VS_TMPDIR/error")
assert_exit_code 0 "$?" "refresh succeeds with advisory findings: $output $(cat "$VS_TMPDIR/error")"
assert_contains "$output" 'DRIFT' 'refresh preserves the registry report on stdout'
assert_contains "$output" 'https://github.com/advisories/GHSA-fixture-low' 'refresh preserves security advisory links on stdout'
assert_contains "$output" 'checked at 2026-11-22T22:15:00Z' 'refresh reports checkedAt in UTC'
assert_contains "$output" 'expires 2026-11-23T22:15:00Z' 'default expiry uses 24 hours'
state=.version-sentinel/audit.json
assert_eq complete "$(jq -r .status "$state")" 'caller project contains successful audit evidence'
assert_eq '' "$(jq -r .session "$state")" 'refresh succeeds without a shell session ID'
python3 -c 'import json, pathlib, sys; assert pathlib.Path(json.loads(pathlib.Path(sys.argv[1]).read_text())["root"]) == pathlib.Path.cwd().resolve()' "$state"
assert_exit_code 0 "$?" 'evidence belongs to the actual project'
jq -e '.checkedAt == 1795385700' "$state" >/dev/null
assert_exit_code 0 "$?" 'reported timestamp matches the saved evidence'
assert_eq "$manifest" "$(cat package.json)" 'refresh preserves the dependency versions'
assert_eq complete "$(jq -r .status .version-sentinel/security.json)" 'security evidence stays separate'
[[ ! -e .version-sentinel/checks.json ]] || _fail 'project refresh must not record individual package checks'

payload='{"tool_name":"Bash","session_id":"host-session","tool_input":{"command":"npm run verify"}}'
output=$(VS_SECURITY_NPM_AUDIT=1 bash "$ROOT/scripts/detect-install-cmd.sh" <<< "$payload")
assert_exit_code 0 "$?" 'named host session can use project audit evidence'
[[ "$output" != *'/vs-refresh'* ]] || _fail "valid refresh must not prompt another refresh in the host session: $output"

payload='{"tool_name":"Bash","session_id":"host-session","tool_input":{"command":"npm install lodash@4.17.20"}}'
output=$(VS_SECURITY_NPM_AUDIT=1 bash "$ROOT/scripts/detect-install-cmd.sh" <<< "$payload")
assert_exit_code 0 "$?" 'package warning allows the install'
assert_contains "$output" '/vs-record' 'missing individual check recommends the recorder'
[[ "$output" != *'/vs-refresh'* ]] || _fail 'missing package evidence calls for an individual check'
rm .version-sentinel/security.json
output=$(VS_SECURITY_NPM_AUDIT=1 bash "$ROOT/scripts/detect-install-cmd.sh" <<< "$payload")
assert_exit_code 0 "$?" 'missing security evidence allows the install'
assert_contains "$output" '/vs-refresh' 'missing security evidence recommends refresh'
[[ "$output" != *'/vs-record'* ]] || _fail 'missing security evidence calls for a project refresh'

output=$(CLAUDE_PLUGIN_OPTION_WINDOW_HOURS=3 bash "$ROOT/scripts/vs-refresh.sh" 2>"$VS_TMPDIR/error")
assert_exit_code 0 "$?" "refresh applies the host's freshness setting: $output $(cat "$VS_TMPDIR/error")"
assert_contains "$output" 'expires 2026-11-23T01:15:00Z' 'expiry uses the configured host window'
output=$(VS_WINDOW_HOURS=2.5 CLAUDE_PLUGIN_OPTION_WINDOW_HOURS=3 bash "$ROOT/scripts/vs-refresh.sh" 2>"$VS_TMPDIR/error")
assert_exit_code 0 "$?" "refresh applies the explicit freshness setting: $output $(cat "$VS_TMPDIR/error")"
assert_contains "$output" 'expires 2026-11-23T00:45:00Z' 'explicit fractional freshness overrides the host setting'

generation=$(jq -r .generation "$state")
output=$(VS_DISABLE=1 bash "$ROOT/scripts/vs-refresh.sh" 2>"$VS_TMPDIR/error")
assert_exit_code 0 "$?" 'disabled refresh preserves the audit status'
[[ "$output" != *'expires'* && "$output" != *'audit completed'* ]] || _fail "disabled refresh claimed success: $output"
assert_eq "$generation" "$(jq -r .generation "$state")" 'disabled refresh leaves prior evidence in place'

output=$(VS_FIXTURE_NETWORK_FAIL=1 bash "$ROOT/scripts/vs-refresh.sh" 2>"$VS_TMPDIR/error")
assert_exit_code 2 "$?" 'refresh preserves the registry failure status'
assert_contains "$output" 'lookup-failed' 'refresh preserves incomplete registry rows on stdout'
assert_contains "$(cat "$VS_TMPDIR/error")" 'audit failed' 'refresh preserves audit diagnostics on stderr'
[[ "$output" != *'expires'* && "$output" != *'audit completed'* ]] || _fail "failed refresh claimed success: $output"
assert_eq pending "$(jq -r .status "$state")" 'failed refresh leaves unsuccessful evidence'

python3 - "$ROOT" <<'PY'
import json
from pathlib import Path
import sys
import tomllib

root = Path(sys.argv[1])
kimi = json.loads((root / 'kimi.plugin.json').read_text())
codex = json.loads((root / '.codex-plugin/plugin.json').read_text())
for name in ('vs-refresh', 'check-versions', 'vs-record'):
    command = tomllib.loads((root / 'commands' / f'{name}.toml').read_text())
    assert command['description'] and command['prompt'], name
    assert (root / kimi['commands'] / f'{name}.md').is_file(), name
    assert (root / '.github/prompts' / f'{name}.prompt.md').is_file(), name
    skill = root / codex['skills'] / name / 'SKILL.md'
    assert skill.read_bytes() == (root / '.agents/skills' / name / 'SKILL.md').read_bytes(), name
PY
assert_exit_code 0 "$?" 'all three actions have discoverable adapters and identical skill mirrors'

finish_test
