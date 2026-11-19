#!/usr/bin/env bash
VS_TEST_NAME=gemini-startup
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/tests/assert.sh"
VS_TMPDIR=$(mktemp -d)
trap 'rm -rf "$VS_TMPDIR"' EXIT
cd "$VS_TMPDIR" || exit 1
printf '%s\n' '-r other.txt' > requirements.txt
for source in startup resume clear; do
  input=$(jq -nc --arg source "$source" '{source:$source}')
  output=$(bash "$ROOT/scripts/session-start.sh" --gemini <<< "$input"); status=$?
  assert_exit_code 0 "$status" "Gemini $source continues"
  printf '%s' "$output" | jq -e '.systemMessage and (.hookSpecificOutput.additionalContext | contains("optional"))' >/dev/null
  assert_exit_code 0 "$?" "Gemini $source has valid optional-audit context"
done
if [[ -d .version-sentinel ]]; then _fail 'startup must not write audit evidence'; fi
# A hung online audit must never be started by the lifecycle hook.
cp -R "$ROOT/scripts" "$VS_TMPDIR/scripts"
printf '%s\n' '#!/usr/bin/env bash' 'touch "$AUDIT_STARTED"' 'sleep 30' > "$VS_TMPDIR/scripts/check-versions.sh"
AUDIT_STARTED="$VS_TMPDIR/audit-started" python3 - "$VS_TMPDIR/scripts/session-start.sh" <<'PY'
import subprocess
import sys
import shutil
from pathlib import Path
bash = shutil.which('bash')
if bash is None:
    raise RuntimeError('Git Bash executable is required for the startup probe')
subprocess.run([str(Path(bash).resolve()), Path(sys.argv[1]).as_posix(), '--gemini'], input='{}', text=True, capture_output=True, timeout=2, check=True)
PY
assert_exit_code 0 "$?" 'startup finishes before host timeout despite slow audit command'
if [[ -f "$VS_TMPDIR/audit-started" ]]; then _fail 'startup invoked online audit'; fi
finish_test
