#!/usr/bin/env bash
# Removing the audit check must let these previously unchecked operations pass.
VS_TEST_NAME="install-audit-gate"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/tests/assert.sh"
VS_TMPDIR=$(mktemp -d)
trap 'rm -rf "$VS_TMPDIR"' EXIT
mkdir -p "$VS_TMPDIR/project" "$VS_TMPDIR/other"
cd "$VS_TMPDIR/project" || exit 1
printf '{"dependencies":{}}\n' > package.json

hook() {
  jq -nc --arg cmd "$1" --arg cwd "$PWD" \
    '{tool_name:"exec_command",cwd:$cwd,tool_input:{command:$cmd}}' |
    bash "$ROOT/scripts/detect-install-cmd.sh" 2>&1
}

for cmd in 'npm install' 'npm ci' 'pnpm install --frozen-lockfile' \
  'yarn install' 'bun install' 'pip install -r requirements.txt' \
  'poetry install' 'uv sync' 'cargo build' 'dotnet restore' \
  'npm run build' 'npm update' 'cargo test' 'uv run app.py'; do
  output=$(hook "$cmd"); code=$?
  assert_exit_code 2 "$code" "unaudited dependency operation blocks: $cmd ($output)"
  assert_contains "$output" "BLOCKED" "dependency operation explains gate: $cmd"
done

for cmd in 'ls -la' 'cat package.json' 'git status' 'npm view lodash version' \
  'bash scripts/check-versions.sh' \
  'bash scripts/vs-record.sh npm lodash 4.17.21 https://www.npmjs.com/package/lodash' \
  'bash scripts/recover-manifest.sh approve package.json --user-confirmed yes'; do
  output=$(hook "$cmd"); code=$?
  assert_exit_code 0 "$code" "inspection and recovery remain available: $cmd ($output)"
done

output=$(printf 'broken JSON' | bash "$ROOT/scripts/detect-install-cmd.sh" 2>&1); code=$?
assert_exit_code 2 "$code" 'malformed hook payload fails closed'

# Context classification is tested independently of audit creation so a wrong
# command cwd cannot be hidden by permissive registry fixtures.
context=$(python3 "$ROOT/scripts/lib/install-context.py" "$PWD" 'cd ../other && npm ci'); code=$?
assert_exit_code 0 "$code" 'literal cd context supported'
assert_contains "$context" "$VS_TMPDIR/other" 'cd selects target project'
context=$(python3 "$ROOT/scripts/lib/install-context.py" "$PWD" 'npm --prefix ../other install'); code=$?
assert_exit_code 0 "$code" 'prefix context supported'
assert_contains "$context" "$VS_TMPDIR/other" 'prefix selects target project'
context=$(python3 "$ROOT/scripts/lib/install-context.py" "$PWD" 'pip install -r custom.txt'); code=$?
assert_exit_code 0 "$code" 'requirements context supported'
assert_contains "$context" 'custom.txt' 'explicit requirements file must exist'
context=$(python3 "$ROOT/scripts/lib/install-context.py" "$PWD" 'cd "$TARGET" && npm ci' 2>&1); code=$?
assert_exit_code 2 "$code" 'dynamic dependency cwd rejected'

# A different ecosystem's successful audit cannot authorize silent manifest creation.
source "$ROOT/tests/registry-fixture.sh"
registry_fixture_setup
rm package.json
printf '[project]\nname = "only-python"\nversion = "1.0.0"\n' > pyproject.toml
bash "$ROOT/scripts/check-versions.sh" >/dev/null || exit 1
bash "$ROOT/scripts/vs-record.sh" npm lodash 4.17.21 https://www.npmjs.com/package/lodash >/dev/null || exit 1
output=$(hook 'npm install lodash@4.17.21'); code=$?
assert_exit_code 2 "$code" 'npm requires its own package.json even after another ecosystem audit'
assert_contains "$output" 'package.json' 'missing ecosystem manifest named'
output=$(hook 'cargo build'); code=$?
assert_exit_code 2 "$code" 'cargo requires Cargo.toml'
# Read-only commands can inspect dynamic paths while dependency work is blocked.
output=$(hook 'cd "$TARGET" && ls'); code=$?
assert_exit_code 0 "$code" 'dynamic read-only inspection remains available'

for cmd in 'env -C ../other npm ci' 'sudo -D ../other npm ci' 'cd ../other || npm ci' 'npm init -y'; do
  output=$(hook "$cmd"); code=$?
  assert_exit_code 2 "$code" "ambiguous cwd or unapproved creation blocks: $cmd"
done

for cmd in 'env -C ../other npm ci' 'sudo -D ../other npm ci'; do
  context=$(python3 "$ROOT/scripts/lib/install-context.py" "$PWD" "$cmd" 2>&1); code=$?
  assert_exit_code 2 "$code" "directory-changing wrapper cannot borrow cwd: $cmd"
done

context=$(python3 "$ROOT/scripts/lib/install-context.py" "$PWD" 'dotnet add Demo.csproj package Polly --version 1.0.0'); code=$?
assert_exit_code 0 "$code" 'dotnet positional project supported'
assert_contains "$context" 'dotnet add package Polly --version 1.0.0' 'dotnet named addition remains visible to version parser'
context=$(python3 "$ROOT/scripts/lib/install-context.py" "$PWD" 'cargo build -r'); code=$?
assert_exit_code 0 "$code" 'cargo release short flag is not requirements file'

# Audit the npm source to isolate cwd and unsupported resolver checks.
printf '{"dependencies":{}}\n' > package.json
bash "$ROOT/scripts/check-versions.sh" >/dev/null || exit 1
for cmd in 'cargo install ripgrep --version 14.1.1' 'uv run --with requests==2.31.0 python --version' 'npm exec --package=lodash@4.17.21 -- node --version'; do
  context=$(python3 "$ROOT/scripts/lib/install-context.py" "$PWD" "$cmd" 2>&1); code=$?
  assert_exit_code 2 "$code" "direct resolver cannot bypass online evidence: $cmd"
done
output=$(jq -nc --arg cwd "$PWD" --arg other "$VS_TMPDIR/other" '{tool_name:"run_shell_command",cwd:$cwd,tool_input:{command:"npm install",dir_path:$other}}' | bash "$ROOT/scripts/detect-install-cmd.sh" 2>&1); code=$?
assert_exit_code 2 "$code" 'Gemini dir_path cannot borrow workspace audit'
output=$(jq -nc --arg cwd "$PWD" '{tool_name:"exec_command",cwd:$cwd,tool_input:{command:"npm install",workdir:"../other"}}' | bash "$ROOT/scripts/detect-install-cmd.sh" 2>&1); code=$?
assert_exit_code 2 "$code" 'relative workdir resolves against payload cwd'

# Native Windows jq emits CRLF. Raw scalar CR must not disable dispatch or
# numeric loops. Keep all real parsing and status codes behind a tiny adapter.
real_jq=$(command -v jq)
mkdir -p "$VS_TMPDIR/crlf-bin"
cat > "$VS_TMPDIR/crlf-bin/jq" <<'CRLF'
#!/usr/bin/env python3
import os, subprocess, sys
p = subprocess.run([os.environ["VS_REAL_JQ"], *sys.argv[1:]], input=sys.stdin.buffer.read(), capture_output=True)
sys.stdout.buffer.write(p.stdout.replace(b"\n", b"\r\n"))
sys.stderr.buffer.write(p.stderr)
sys.exit(p.returncode)
CRLF
chmod +x "$VS_TMPDIR/crlf-bin/jq"
output=$(jq -nc --arg cwd "$PWD" '{tool_name:"Bash",cwd:$cwd,tool_input:{command:"npm install unrecorded@99.99.99"}}' | VS_REAL_JQ="$real_jq" PATH="$VS_TMPDIR/crlf-bin:$PATH" bash "$ROOT/scripts/detect-install-cmd.sh" 2>&1); code=$?
assert_exit_code 2 "$code" 'CRLF jq output cannot bypass package checks'

output=$(VS_REAL_JQ="$real_jq" PATH="$VS_TMPDIR/crlf-bin:$PATH" bash "$ROOT/scripts/check-versions.sh" 2>&1); code=$?
assert_exit_code 0 "$code" 'CRLF jq supports successful online-fixture audit'
output=$(VS_REAL_JQ="$real_jq" PATH="$VS_TMPDIR/crlf-bin:$PATH" bash "$ROOT/scripts/vs-record.sh" npm lodash 4.17.21 https://www.npmjs.com/package/lodash 2>&1); code=$?
assert_exit_code 0 "$code" 'CRLF jq supports successful online-fixture recording'
output=$(jq -nc --arg cwd "$PWD" '{tool_name:"Bash",cwd:$cwd,tool_input:{command:"npm install lodash@4.17.21"}}' | VS_REAL_JQ="$real_jq" PATH="$VS_TMPDIR/crlf-bin:$PATH" bash "$ROOT/scripts/detect-install-cmd.sh" 2>&1); code=$?
assert_exit_code 0 "$code" 'CRLF jq permits audited online-verified dependency'

finish_test
