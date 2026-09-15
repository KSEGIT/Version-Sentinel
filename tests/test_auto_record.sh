#!/usr/bin/env bash
# Tests scripts/auto-record.sh: PostToolUse:Bash → sidecar auto-entry on successful installs.
set -u
VS_TEST_NAME="auto-record"
source "$(dirname "$0")/assert.sh"

VS_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$VS_TMPDIR"' EXIT
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$ROOT/scripts/auto-record.sh"
SIDECAR=".version-sentinel/checks.json"

# Guarded: several `rm -rf .version-sentinel` calls run below; under `set -u`
# without `set -e` a failed cd would leave them deleting the caller's real
# project state.
cd "$VS_TMPDIR" || { echo "FAIL [$VS_TEST_NAME]: cannot cd to $VS_TMPDIR" >&2; exit 1; }

# Helper: count entries in sidecar (0 if file missing/invalid)
count_entries() {
  if [[ ! -f "$SIDECAR" ]]; then echo 0; return; fi
  jq '.entries | length' "$SIDECAR" 2>/dev/null || echo 0
}

# --- Case 1: successful npm install → entry added, source starts "auto-recorded:" ---
rm -rf .version-sentinel
json='{"tool_name":"Bash","tool_input":{"command":"npm install lodash@4.17.21"},"tool_response":{"exit_code":0}}'
out=$(echo "$json" | bash "$SCRIPT" 2>&1; echo "exit=$?")
assert_contains "$out" "exit=0" "success install → exit 0"
assert_eq "1" "$(count_entries)" "success install → 1 sidecar entry"
src=$(jq -r '.entries[0].source' "$SIDECAR")
case "$src" in
  "auto-recorded:"*) ;;
  *) _fail "entry source should start with 'auto-recorded:', got: $src" ;;
esac
assert_eq "npm"      "$(jq -r '.entries[0].ecosystem' "$SIDECAR")" "entry ecosystem=npm"
assert_eq "lodash"   "$(jq -r '.entries[0].pkg'       "$SIDECAR")" "entry pkg=lodash"
assert_eq "4.17.21"  "$(jq -r '.entries[0].version'   "$SIDECAR")" "entry version=4.17.21"

# A versioned npm alias records the real registry target and version.
rm -rf .version-sentinel
json='{"tool_name":"Bash","tool_input":{"command":"npm install compat@npm:lodash@4.17.21"},"tool_response":{"exit_code":0}}'
echo "$json" | bash "$SCRIPT" >/dev/null 2>&1
assert_eq "1" "$(count_entries)" "versioned alias → 1 sidecar entry"
assert_eq "lodash" "$(jq -r '.entries[0].pkg' "$SIDECAR")" "versioned alias records real target"
assert_eq "4.17.21" "$(jq -r '.entries[0].version' "$SIDECAR")" "versioned alias records target version"

# Exact selectors for every ecosystem are normalized before recording.
for _case in \
  $'npm install lodash@=4.17.21\tnpm\tlodash\t4.17.21' \
  $'pip install requests==2.31.0\tpip\trequests\t2.31.0' \
  $'poetry add flask@=3.0.0\tpip\tflask\t3.0.0' \
  $'cargo add serde@=1.0.196\tcargo\tserde\t1.0.196'; do
  IFS=$'\t' read -r _command _eco _pkg _ver <<< "$_case"
  rm -rf .version-sentinel
  json=$(jq -nc --arg command "$_command" '{tool_name:"Bash",tool_input:{command:$command},tool_response:{exit_code:0}}')
  echo "$json" | bash "$SCRIPT" >/dev/null 2>&1
  assert_eq "1" "$(count_entries)" "exact selector records one entry: $_command"
  assert_eq "$_eco" "$(jq -r '.entries[0].ecosystem' "$SIDECAR")" "exact selector ecosystem: $_command"
  assert_eq "$_pkg" "$(jq -r '.entries[0].pkg' "$SIDECAR")" "exact selector package: $_command"
  assert_eq "$_ver" "$(jq -r '.entries[0].version' "$SIDECAR")" "exact selector normalized version: $_command"
done

# --- Case 2: failed install (non-zero exit_code) → no entry added ---
rm -rf .version-sentinel
json='{"tool_name":"Bash","tool_input":{"command":"npm install bogus@9.9.9"},"tool_response":{"exit_code":1}}'
out=$(echo "$json" | bash "$SCRIPT" 2>&1; echo "exit=$?")
assert_contains "$out" "exit=0" "failed install → exit 0"
assert_eq "0" "$(count_entries)" "failed install → no sidecar entry"

# --- Case 2a: unpinned, floating and non-registry targets are never records ---
for _c in "npm install lodash" \
          "npm install lodash@latest" \
          "npm install lodash@beta" \
          "npm install lodash@^1.2.3" \
          "npm install lodash@!=1.2.3" \
          "npm install lodash@1.*" \
          'npm install "lodash@>=1.2.3 <2.0.0"' \
          "pip install requests>=2.31.0" \
          "pip install requests!=2.31.0" \
          "pip install requests==2.*" \
          'pip install "requests>=2,<3"' \
          "poetry add flask@^3.0.0" \
          "poetry add flask@!=3.0.0" \
          "poetry add flask@3.*" \
          'poetry add "flask@>=3,<4"' \
          "cargo add serde@1.0.196" \
          "cargo add serde@^1.0.196" \
          "cargo add serde@!=1.0.196" \
          "cargo add serde@1.*" \
          'cargo add "serde@>=1,<2"' \
          "pip install requests" \
          "cargo add serde" \
          "dotnet add package Newtonsoft.Json" \
          "npm install ./local-package" \
          "npm install workspace:*" \
          "npm install git+https://example.com/repo.git" \
          "pip install -r requirements.txt" \
          "poetry add ../local-package" \
          "cargo add --path ../local-crate" \
          "cargo add --git https://example.com/repo.git"; do
  rm -rf .version-sentinel
  json=$(jq -nc --arg command "$_c" '{tool_name:"Bash",tool_input:{command:$command},tool_response:{exit_code:0}}')
  echo "$json" | bash "$SCRIPT" >/dev/null 2>&1
  assert_eq "0" "$(count_entries)" "no sidecar entry for unrecordable target: $_c"
done

# --- Case 2b: JSON boolean success=false → no entry added ---
rm -rf .version-sentinel
json='{"tool_name":"Bash","tool_input":{"command":"npm install bogus@9.9.9"},"tool_response":{"success":false}}'
out=$(echo "$json" | bash "$SCRIPT" 2>&1; echo "exit=$?")
assert_contains "$out" "exit=0" "success=false → exit 0"
assert_eq "0" "$(count_entries)" "success=false → no sidecar entry"

# --- Case 3: tool_name != Bash → no-op ---
rm -rf .version-sentinel
json='{"tool_name":"Edit","tool_input":{"command":"npm install lodash@4.17.21"},"tool_response":{"exit_code":0}}'
out=$(echo "$json" | bash "$SCRIPT" 2>&1; echo "exit=$?")
assert_contains "$out" "exit=0" "non-Bash tool → exit 0"
assert_eq "0" "$(count_entries)" "non-Bash tool → no sidecar entry"

# --- Case 4: malformed JSON on stdin → no-op ---
rm -rf .version-sentinel
out=$(echo "not-json-at-all{" | bash "$SCRIPT" 2>&1; echo "exit=$?")
assert_contains "$out" "exit=0" "bad JSON → exit 0"
assert_eq "0" "$(count_entries)" "bad JSON → no sidecar entry"

# --- Case 5: CLAUDE_PLUGIN_OPTION_DISABLE=true → no-op ---
rm -rf .version-sentinel
json='{"tool_name":"Bash","tool_input":{"command":"npm install lodash@4.17.21"},"tool_response":{"exit_code":0}}'
out=$(echo "$json" | CLAUDE_PLUGIN_OPTION_DISABLE=true bash "$SCRIPT" 2>&1; echo "exit=$?")
assert_contains "$out" "exit=0" "DISABLE=true → exit 0"
assert_eq "0" "$(count_entries)" "DISABLE=true → no sidecar entry"

# --- Laundering guard: a command that installs NOTHING must never be recorded ---
# `env -S true <pm> install <pkg>` runs `true`, installs nothing, exits 0 and has
# no compound operators, so every other guard in auto-record.sh passes. If the
# prefix stripper is used here, it records a check for <pkg> and a genuine
# install of that package is then allowed with no check ever performed. This is
# why auto-record.sh calls parse_install_cmd_strict.
# A multi-line command whose BODY merely contains an install line installs
# nothing: the text is heredoc data, a generated script, or a commit message.
# parse_install_cmd splits on newlines, so that line becomes its own segment and
# starts with a manager -- prefix stripping is not involved at all, which is why
# the strict/lenient split alone does not close this.
rm -rf .version-sentinel
json='{"tool_name":"Bash","tool_input":{"command":"cat > notes.txt <<EOF\nnpm install evilpkg@9.9.9\nEOF"},"tool_response":{"exit_code":0}}'
echo "$json" | bash "$SCRIPT" >/dev/null 2>&1
assert_eq "0" "$(count_entries)" "heredoc body containing an install is not recorded"

rm -rf .version-sentinel
json='{"tool_name":"Bash","tool_input":{"command":"cat > build.sh <<SH\ncd app\nnpm install evilpkg@9.9.9\nSH"},"tool_response":{"exit_code":0}}'
echo "$json" | bash "$SCRIPT" >/dev/null 2>&1
assert_eq "0" "$(count_entries)" "generated script body is not recorded"

for _c in "env -S npm install evilpkg@9.9.9" \
          "env -S true npm install evilpkg@9.9.9" \
          "env -i true npm install evilpkg@9.9.9" \
          "xargs -t echo npm install evilpkg@9.9.9" \
          "sudo npm install evilpkg@9.9.9"; do
  rm -rf .version-sentinel
  json="{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"$_c\"},\"tool_response\":{\"exit_code\":0}}"
  echo "$json" | bash "$SCRIPT" >/dev/null 2>&1
  assert_eq "0" "$(count_entries)" "no sidecar entry for: $_c"
done
rm -rf .version-sentinel

cd "$OLDPWD"


finish_test
