#!/usr/bin/env bash
# End-to-end: platform-shaped PreToolUse payloads (Gemini, VS Code Copilot,
# Codex, Kimi) must be normalized and blocked/allowed exactly like Claude ones.
VS_TEST_NAME="platform-payloads"
TESTS_DIR="$(cd "$(dirname "$0")" && pwd)"
FIXTURES="$TESTS_DIR/fixtures"
source "$TESTS_DIR/assert.sh"

VS_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$VS_TMPDIR"' EXIT

SCRIPTS="$(cd "$(dirname "$0")/.." && pwd)/scripts"
DETECT_EDIT="$SCRIPTS/detect-manifest-edit.sh"
DETECT_CMD="$SCRIPTS/detect-install-cmd.sh"
RECORD="$SCRIPTS/vs-record.sh"

cd "$VS_TMPDIR"
cat > package.json <<EOF
{
  "name": "fixture",
  "version": "1.0.0",
  "dependencies": {
    "express": "4.19.2"
  }
}
EOF

substitute() {
  sed "s|{{CWD}}|$VS_TMPDIR|g" "$1"
}

record_lodash() {
  bash "$RECORD" npm lodash 4.17.21 "https://www.npmjs.com/package/lodash" >/dev/null 2>&1
}

# --- Gemini write_file (=Write) adds lodash → block, then allowed after record ---
input=$(substitute "$FIXTURES/payloads/gemini-write-file.json")
result=$(echo "$input" | bash "$DETECT_EDIT" 2>&1; echo "exit=$?")
assert_contains "$result" "BLOCKED" "gemini write_file: blocked"
assert_contains "$result" "lodash" "gemini write_file: names pkg"
assert_contains "$result" "exit=2" "gemini write_file: exit 2"
record_lodash
result=$(echo "$input" | bash "$DETECT_EDIT" 2>&1; echo "exit=$?")
assert_contains "$result" "exit=0" "gemini write_file: exit 0 after record"
rm -rf .version-sentinel

# --- VS Code Copilot editFiles (=Edit) adds lodash → block, then allowed ---
input=$(substitute "$FIXTURES/payloads/vscode-editFiles.json")
result=$(echo "$input" | bash "$DETECT_EDIT" 2>&1; echo "exit=$?")
assert_contains "$result" "BLOCKED" "copilot editFiles: blocked"
assert_contains "$result" "lodash" "copilot editFiles: names pkg"
assert_contains "$result" "exit=2" "copilot editFiles: exit 2"
record_lodash
result=$(echo "$input" | bash "$DETECT_EDIT" 2>&1; echo "exit=$?")
assert_contains "$result" "exit=0" "copilot editFiles: exit 0 after record"
rm -rf .version-sentinel

# --- Codex apply_patch: patch header identifies manifest, full content carried → block ---
input=$(substitute "$FIXTURES/payloads/codex-apply-patch.json")
result=$(echo "$input" | bash "$DETECT_EDIT" 2>&1; echo "exit=$?")
assert_contains "$result" "BLOCKED" "codex apply_patch: blocked"
assert_contains "$result" "lodash" "codex apply_patch: names pkg"
assert_contains "$result" "exit=2" "codex apply_patch: exit 2"
record_lodash
result=$(echo "$input" | bash "$DETECT_EDIT" 2>&1; echo "exit=$?")
assert_contains "$result" "exit=0" "codex apply_patch: exit 0 after record"
rm -rf .version-sentinel

# --- Codex apply_patch: patch only, no full content → fail-open with note ---
input=$(substitute "$FIXTURES/payloads/codex-apply-patch-patch-only.json")
result=$(echo "$input" | bash "$DETECT_EDIT" 2>&1; echo "exit=$?")
assert_contains "$result" "exit=0" "codex apply_patch patch-only: fail-open exit 0"
assert_contains "$result" "fail-open" "codex apply_patch patch-only: stderr note"

# --- Kimi Bash install (same name as Claude) → block, then allowed ---
input=$(cat "$FIXTURES/payloads/kimi-bash-install.json")
result=$(echo "$input" | bash "$DETECT_CMD" 2>&1; echo "exit=$?")
assert_contains "$result" "BLOCKED" "kimi Bash install: blocked"
assert_contains "$result" "lodash" "kimi Bash install: names pkg"
assert_contains "$result" "exit=2" "kimi Bash install: exit 2"
record_lodash
result=$(echo "$input" | bash "$DETECT_CMD" 2>&1; echo "exit=$?")
assert_contains "$result" "exit=0" "kimi Bash install: exit 0 after record"
rm -rf .version-sentinel

# --- Gemini run_shell_command (=Bash) install → block, then allowed ---
input=$(cat "$FIXTURES/payloads/gemini-run-shell-install.json")
result=$(echo "$input" | bash "$DETECT_CMD" 2>&1; echo "exit=$?")
assert_contains "$result" "BLOCKED" "gemini run_shell_command install: blocked"
assert_contains "$result" "lodash" "gemini run_shell_command install: names pkg"
assert_contains "$result" "exit=2" "gemini run_shell_command install: exit 2"
record_lodash
result=$(echo "$input" | bash "$DETECT_CMD" 2>&1; echo "exit=$?")
assert_contains "$result" "exit=0" "gemini run_shell_command install: exit 0 after record"
rm -rf .version-sentinel

cd "$OLDPWD"
finish_test
