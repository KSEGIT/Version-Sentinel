#!/usr/bin/env bash
# Startup only audits dependency projects, and only mutates payload cwd state.
VS_TEST_NAME=startup-scope
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/tests/assert.sh"
VS_TMPDIR=$(mktemp -d)
trap 'rm -rf "$VS_TMPDIR"' EXIT
mkdir -p "$VS_TMPDIR/bin" "$VS_TMPDIR/launch" "$VS_TMPDIR/empty" "$VS_TMPDIR/empty-repo" "$VS_TMPDIR/project"
cat > "$VS_TMPDIR/bin/curl" <<'CURL'
#!/usr/bin/env bash
printf 'request\n' >> "$AUDIT_REQUEST_LOG"
[[ "${AUDIT_FIXTURE_FAIL:-0}" == 1 ]] && exit 7
case "${@: -1}" in
  https://registry.npmjs.org/lodash)
    printf '%s\n' '{"name":"lodash","dist-tags":{"latest":"4.17.21"},"versions":{"4.17.21":{}}}' ;;
  *) exit 22 ;;
esac
CURL
chmod +x "$VS_TMPDIR/bin/curl"
export PATH="$VS_TMPDIR/bin:$PATH" VS_ETAG_DISABLE=1 VS_REGISTRY_RETRIES=1 VS_REGISTRY_RETRY_DELAY=0
export AUDIT_REQUEST_LOG="$VS_TMPDIR/requests"
: > "$AUDIT_REQUEST_LOG"
printf 'Gmail task\n' > "$VS_TMPDIR/empty/README.md"
git -C "$VS_TMPDIR/empty-repo" init -q
cd "$VS_TMPDIR/launch" || exit 1
printf '{"dependencies":{"lodash":"4.17.21"}}' > package.json

# Neither fresh empty folders nor empty repositories need registry requests.
# The launch manifest must not cause auditing or create launch state.
for target in empty empty-repo; do
  for mode in '' --gemini --copilot; do
    input=$(jq -nc --arg cwd "$VS_TMPDIR/$target" '{cwd:$cwd,session_id:"empty-session"}')
    output=$(AUDIT_FIXTURE_FAIL=1 bash "$ROOT/scripts/session-start.sh" "$mode" <<< "$input" 2>"$VS_TMPDIR/startup.err"); status=$?
    assert_exit_code 0 "$status" "fresh $target startup succeeds ($mode)"
    assert_eq '' "$output" "fresh $target emits no context ($mode)"
    assert_eq '' "$(cat "$VS_TMPDIR/startup.err")" "fresh $target emits no errors ($mode)"
    [[ ! -e .version-sentinel ]] || _fail "payload startup created launch state ($target $mode)"
    if [[ -f "$VS_TMPDIR/$target/.version-sentinel/audit.json" ]]; then
      assert_eq pending "$(jq -r .status "$VS_TMPDIR/$target/.version-sentinel/audit.json")" "empty startup never completes evidence ($mode)"
    fi
  done
done
assert_eq '' "$(cat "$AUDIT_REQUEST_LOG")" 'empty startup never contacts registry'

# A successful launch audit must survive startup targeting another project.
bash "$ROOT/scripts/check-versions.sh" >/dev/null 2>&1
assert_exit_code 0 "$?" 'launch fixture has completed audit'
cp .version-sentinel/audit.json "$VS_TMPDIR/launch-before.json"
printf '{"dependencies":{"lodash":"4.17.21"}}' > "$VS_TMPDIR/project/package.json"
for target in empty project; do
  input=$(jq -nc --arg cwd "$VS_TMPDIR/$target" '{cwd:$cwd,session_id:"target-session"}')
  output=$(bash "$ROOT/scripts/session-start.sh" <<< "$input" 2>"$VS_TMPDIR/startup.err"); status=$?
  assert_exit_code 0 "$status" "$target payload startup succeeds from audited launch"
  cmp -s .version-sentinel/audit.json "$VS_TMPDIR/launch-before.json"
  assert_exit_code 0 "$?" "$target payload startup preserves launch evidence"
done
VS_SESSION_ID=target-session bash "$ROOT/scripts/audit-state.sh" gate "$VS_TMPDIR/project" >/dev/null 2>&1
assert_exit_code 0 "$?" 'target project gets session-bound audit evidence'
VS_SESSION_ID=other-session bash "$ROOT/scripts/audit-state.sh" gate "$VS_TMPDIR/project" >/dev/null 2>&1
assert_exit_code 2 "$?" 'target audit rejects another session'

# Missing startup prerequisites revoke target evidence before failing, even
# when jq is unavailable to read cwd. Launch evidence must remain unchanged.
mkdir "$VS_TMPDIR/startup-bin"
startup_tool() {
  local original
  original=$(command -v "$1") || return
  printf '#!/bin/bash\nexec %q "$@"\n' "$original" > "$VS_TMPDIR/startup-bin/$1"
  chmod +x "$VS_TMPDIR/startup-bin/$1"
}
for prerequisite in bash cat python3; do
  startup_tool "$prerequisite"
done
# Isolate the missing prerequisite from the Windows path mapper.
startup_target="$VS_TMPDIR/project"
if command -v cygpath >/dev/null 2>&1; then
  startup_target=$(cygpath -m "$startup_target")
fi
for missing_prerequisite in curl jq; do
  if [[ "$missing_prerequisite" == curl ]]; then
    startup_tool jq
  else
    rm "$VS_TMPDIR/startup-bin/jq"
    startup_tool curl
  fi
  (cd "$VS_TMPDIR/project" && bash "$ROOT/scripts/check-versions.sh" >/dev/null 2>&1)
  assert_exit_code 0 "$?" "target has fresh evidence before missing $missing_prerequisite"
  input=$(jq -nc --arg cwd "$startup_target" '{cwd:$cwd}')
  output=$(PATH="$VS_TMPDIR/startup-bin" /bin/bash "$ROOT/scripts/session-start.sh" <<< "$input" 2>&1); status=$?
  assert_exit_code 2 "$status" "missing $missing_prerequisite fails startup"
  assert_contains "$output" "$missing_prerequisite missing" "missing startup prerequisite stays visible"
  cmp -s .version-sentinel/audit.json "$VS_TMPDIR/launch-before.json"
  assert_exit_code 0 "$?" "missing $missing_prerequisite preserves unrelated launch evidence"
  bash "$ROOT/scripts/audit-state.sh" gate "$VS_TMPDIR/project" >/dev/null 2>&1
  assert_exit_code 2 "$?" "missing $missing_prerequisite revokes target evidence after PATH is restored"
done

# Canonical JSON transport keeps spaces/Unicode and rejects line breaks that
# Bash command substitution would trim into a different directory.
mkdir "$VS_TMPDIR/café project" "$VS_TMPDIR/linebreak"
if [[ "$(python3 -c 'import os; print(os.name)')" != nt ]]; then
  mkdir "$VS_TMPDIR/linebreak"$'\n'
fi
printf '{}' > "$VS_TMPDIR/café project/package.json"
input=$(jq -nc --arg cwd "$VS_TMPDIR/café project" '{cwd:$cwd,session_id:"unicode-session"}')
output=$(bash "$ROOT/scripts/session-start.sh" <<< "$input" 2>"$VS_TMPDIR/startup.err"); status=$?
assert_exit_code 0 "$status" 'startup preserves Unicode and spaces in payload cwd'
VS_SESSION_ID=unicode-session bash "$ROOT/scripts/audit-state.sh" gate "$VS_TMPDIR/café project" >/dev/null 2>&1
assert_exit_code 0 "$?" 'Unicode target receives its own session evidence'
input=$(jq -nc --arg cwd "$VS_TMPDIR/linebreak"$'\n' '{cwd:$cwd}')
output=$(bash "$ROOT/scripts/session-start.sh" <<< "$input" 2>&1); status=$?
assert_exit_code 2 "$status" 'line break cwd fails before ambiguous shell transport'
[[ ! -e "$VS_TMPDIR/linebreak/.version-sentinel" ]] || _fail 'line break cwd touched trimmed sibling'
[[ ! -e "$VS_TMPDIR/linebreak"$'\n'/.version-sentinel ]] || _fail 'rejected line break cwd created state'
cmp -s .version-sentinel/audit.json "$VS_TMPDIR/launch-before.json"
assert_exit_code 0 "$?" 'unsupported cwd leaves launch evidence unchanged'

# Windows path mapping can trim CR/LF; reject raw cwd before that conversion.
python3 - "$ROOT" "$VS_TMPDIR" <<'PY'
import importlib.util
import io
import json
from pathlib import Path
import sys
from unittest.mock import patch

sys.path.insert(0, str(Path(sys.argv[1]) / 'scripts' / 'lib'))
spec = importlib.util.spec_from_file_location('project_state', Path(sys.argv[1]) / 'scripts' / 'lib' / 'project-state.py')
state = importlib.util.module_from_spec(spec)
spec.loader.exec_module(state)
fallback = Path(sys.argv[2]) / 'bootstrap-fallback'
trimmed = Path(sys.argv[2]) / 'mapped-linebreak'
fallback.mkdir()
trimmed.mkdir()
original_resolve = state.resolve_path

def mapper(value, base=None):
    return trimmed if value == '/msys/project\n' else original_resolve(value, base)

with patch.object(state.sys, 'stdin', io.StringIO(json.dumps({'cwd': '/msys/project\n'}))), patch.object(state, 'resolve_path', side_effect=mapper):
    try:
        state.startup_invalidate(str(fallback))
    except ValueError:
        pass
    else:
        raise AssertionError('startup accepted cwd after mapper trimmed its newline')
assert not (trimmed / '.version-sentinel').exists(), 'mapper redirected startup state to trimmed sibling'
assert not (fallback / '.version-sentinel').exists(), 'invalid cwd changed fallback state'
PY
assert_exit_code 0 "$?" 'raw cwd is rejected before a Windows mapper can trim it'

# Wrong-root reads are also forbidden: corrupt launch state must not affect target.
printf 'invalid launch audit' > .version-sentinel/audit.json
for target in empty project; do
  input=$(jq -nc --arg cwd "$VS_TMPDIR/$target" '{cwd:$cwd,session_id:"target-session"}')
  output=$(bash "$ROOT/scripts/session-start.sh" <<< "$input" 2>"$VS_TMPDIR/startup.err"); status=$?
  assert_exit_code 0 "$status" "corrupt launch state cannot fail $target startup"
  assert_eq 'invalid launch audit' "$(cat .version-sentinel/audit.json)" 'launch state remains untouched'
done

cd "$VS_TMPDIR/empty" || exit 1
bash "$ROOT/scripts/check-versions.sh" >/dev/null 2>&1
assert_exit_code 2 "$?" 'direct empty audit still fails'
bash "$ROOT/scripts/audit-state.sh" gate "$PWD" >/dev/null 2>&1
assert_exit_code 2 "$?" 'empty project gate remains closed'
input=$(jq -nc --arg cwd "$PWD" '{cwd:$cwd,tool_name:"Bash",tool_input:{command:"npm install"}}')
bash "$ROOT/scripts/detect-install-cmd.sh" <<< "$input" >/dev/null 2>&1
assert_exit_code 2 "$?" 'empty startup cannot authorize dependency installation'
# Even old empty success evidence must not survive a skipped startup.
jq -nc --arg root "$PWD" '{root:$root,required:[],files:{},status:"complete",checkedAt:9999999999}' > .version-sentinel/audit.json
output=$(bash "$ROOT/scripts/session-start.sh" <<< '{}' 2>"$VS_TMPDIR/startup.err"); status=$?
assert_exit_code 0 "$status" 'stale empty success does not force a false audit'
assert_eq '' "$output" 'stale empty success is skipped silently'
assert_eq pending "$(jq -r .status .version-sentinel/audit.json)" 'skipped startup revokes stale success'

# Existing project evidence, tracked deletion, and orphan locks are not empty.
cd "$VS_TMPDIR/project" || exit 1
rm package.json
mkdir "$VS_TMPDIR/tracked" "$VS_TMPDIR/orphan"
git -C "$VS_TMPDIR/tracked" init -q
printf '{}' > "$VS_TMPDIR/tracked/package.json"
git -C "$VS_TMPDIR/tracked" add package.json
rm "$VS_TMPDIR/tracked/package.json"
printf '{}' > "$VS_TMPDIR/orphan/package-lock.json"
for target in project tracked orphan; do
  cd "$VS_TMPDIR/$target" || exit 1
  output=$(bash "$ROOT/scripts/session-start.sh" <<< '{}' 2>"$VS_TMPDIR/startup.err"); status=$?
  assert_exit_code 0 "$status" "$target missing manifest is advisory"
  assert_contains "$output" 'Required manifest is missing: package.json' "$target missing manifest stays visible"
  bash "$ROOT/scripts/audit-state.sh" gate "$PWD" >/dev/null 2>&1
  assert_exit_code 2 "$?" "$target missing manifest keeps gate closed"
done
# NuGet dependency files cannot identify a source filename, but are not empty.
for dependency_file in packages.lock.json Directory.Packages.props; do
  mkdir "$VS_TMPDIR/$dependency_file"
  cd "$VS_TMPDIR/$dependency_file" || exit 1
  printf '{}' > "$dependency_file"
  for mode in '' --gemini --copilot; do
    output=$(bash "$ROOT/scripts/session-start.sh" "$mode" <<< '{}' 2>"$VS_TMPDIR/startup.err"); status=$?
    assert_exit_code 0 "$status" "$dependency_file missing manifest is advisory ($mode)"
    assert_contains "$output" 'Required dependency manifest is missing' "$dependency_file is not an empty workspace ($mode)"
    bash "$ROOT/scripts/audit-state.sh" gate "$PWD" >/dev/null 2>&1
    assert_exit_code 2 "$?" "$dependency_file without manifest keeps gate closed ($mode)"
  done
done
# Recovery after a prior success still needs a new audit.
cd "$VS_TMPDIR/project" || exit 1
printf '{"dependencies":{"lodash":"4.17.21"}}' > package.json
bash "$ROOT/scripts/audit-state.sh" gate "$PWD" >/dev/null 2>&1
assert_exit_code 2 "$?" 'restoring required manifest does not restore prior success'
bash "$ROOT/scripts/check-versions.sh" >/dev/null 2>&1
assert_exit_code 0 "$?" 'restored project can complete a fresh audit'
finish_test
