#!/usr/bin/env bash
# Exercise the package that the Claude directory receives, outside the checkout.
set -u
VS_TEST_NAME="claude-bundle"
source "$(dirname "$0")/assert.sh"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VS_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$VS_TMPDIR"' EXIT
PLUGIN="$VS_TMPDIR/plugin with spaces"
PROJECT="$VS_TMPDIR/project with spaces"
mkdir -p "$PROJECT"

output=$(bash "$ROOT/tools/build-claude-plugin.sh" "$PLUGIN" 2>&1)
status=$?
assert_exit_code 0 "$status" "bundle builds into a new path with spaces: $output"
if [[ "$status" -ne 0 ]]; then
  finish_test
  exit $?
fi

python3 - "$ROOT" "$PLUGIN" <<'PY'
import json
from pathlib import Path
import re
import shlex
import sys

root, bundle = map(Path, sys.argv[1:])
runtime = {p.relative_to(root) for p in (root / 'scripts').rglob('*')
           if p.is_file() and p.suffix in {'.sh', '.py'}}
commands = {p.relative_to(root) for p in (root / 'commands').glob('*.md')}
agents = {p.relative_to(root) for p in (root / 'agents').glob('*.md')}
expected = runtime | commands | agents | {Path(p) for p in (
    '.claude-plugin/plugin.json', 'hooks/hooks.json',
    'skills/version-sentinel/SKILL.md', 'LICENSE', 'PRIVACY.md',
    'docs/enforcement.md', 'README.md')}
actual = {p.relative_to(bundle) for p in bundle.rglob('*') if p.is_file()}
assert actual == expected, f'bundle contents differ: extra={actual - expected}, missing={expected - actual}'
assert not any(p.is_symlink() for p in bundle.rglob('*')), 'bundle contains a symlink'
for relative in expected - {Path('README.md')}:
    assert (root / relative).read_bytes() == (bundle / relative).read_bytes(), relative
readme = (bundle / 'README.md').read_text()
assert readme == (root / 'packaging/claude/README.md').read_text()
assert len(readme.split()) >= 40, 'package README is too short for the directory'
assert not re.search(r'!\[|<img|curl.*\|.*(?:sh|bash)|wget.*\|.*(?:sh|bash)', readme)

manifest = json.loads((bundle / '.claude-plugin/plugin.json').read_text())
for field in ('commands', 'agents'):
    for path in manifest[field]:
        assert (bundle / path).is_file(), f'{field}: {path}'
assert (bundle / manifest['skills'] / 'version-sentinel/SKILL.md').is_file()
hooks = json.loads((bundle / 'hooks/hooks.json').read_text())['hooks']
for groups in hooks.values():
    for group in groups:
        for hook in group['hooks']:
            for token in shlex.split(hook['command']):
                if token.startswith('${CLAUDE_PLUGIN_ROOT}/'):
                    assert (bundle / token.removeprefix('${CLAUDE_PLUGIN_ROOT}/')).is_file(), token
PY
assert_exit_code 0 "$?" "bundle contains only complete, unchanged Claude runtime files"

# A second build must not remove or overwrite an existing destination.
printf '%s\n' 'keep this file' > "$PLUGIN/sentinel.txt"
output=$(bash "$ROOT/tools/build-claude-plugin.sh" "$PLUGIN" 2>&1)
status=$?
assert_exit_code 1 "$status" "existing destination is rejected: $output"
assert_eq 'keep this file' "$(cat "$PLUGIN/sentinel.txt")" "existing destination contents survive"
output=$(cd "$VS_TMPDIR" && bash "$ROOT/tools/build-claude-plugin.sh" relative-output 2>&1)
status=$?
assert_exit_code 1 "$status" "relative destination is rejected: $output"

source "$ROOT/tests/registry-fixture.sh"
registry_fixture_setup
export CLAUDE_PLUGIN_ROOT="$PLUGIN" VS_DISABLE=0

run_package_command() {
  local file="$1" command
  command=$(sed -n 's/^!\(bash .*\)$/\1/p' "$PLUGIN/$file")
  command="${command//\$ARGUMENTS/npm lodash 4.17.21 https:\/\/www.npmjs.com\/package\/lodash}"
  (cd "$PROJECT" && bash -c "$command")
}

output=$(run_package_command commands/vs-record.md 2>&1)
status=$?
assert_exit_code 0 "$status" "shipped recorder command executes: $output"
assert_eq '4.17.21' "$(jq -r '.entries[0].version' "$PROJECT/.version-sentinel/checks.json")" \
  "shipped recorder records verified fixture version"
printf '%s\n' '{"dependencies":{"lodash":"4.17.21"}}' > "$PROJECT/package.json"
output=$(run_package_command commands/check-versions.md 2>&1)
status=$?
assert_exit_code 0 "$status" "shipped audit command executes: $output"
assert_contains "$output" "lodash" "shipped audit reports the project package"
hook_command=$(jq -r '.hooks.SessionStart[0].hooks[0].command' "$PLUGIN/hooks/hooks.json")
output=$(cd "$PROJECT" && printf '{"cwd":"%s","session_id":"bundle-fixture"}\n' "$PROJECT" | bash -c "$hook_command" 2>&1)
status=$?
assert_exit_code 0 "$status" "shipped startup hook executes: $output"
assert_file_exists "$PROJECT/.version-sentinel/audit.json" "shipped startup hook creates audit evidence"

finish_test
