#!/usr/bin/env bash
# Tests scripts/lib/platform.sh: normalize_tool_name mappings per platform.
set -u
VS_TEST_NAME="platform-normalize"
source "$(dirname "$0")/assert.sh"

LIB="$(cd "$(dirname "$0")/.." && pwd)/scripts/lib/platform.sh"

norm() {
  env -i PATH="$PATH" bash -c "
    set -u
    source '$LIB'
    source '$LIB'   # double-source must be a no-op
    normalize_tool_name \"\$1\"
  " _ "$1"
}

# --- Shell tools → Bash ---
assert_eq "Bash" "$(norm run_shell_command)"   "Gemini run_shell_command → Bash"
assert_eq "Bash" "$(norm exec_command)"        "Codex exec_command → Bash"
assert_eq "Bash" "$(norm runTerminalCommand)"  "Copilot runTerminalCommand → Bash"
assert_eq "Bash" "$(norm terminal)"            "terminal → Bash"

# --- File-create tools → Write ---
assert_eq "Write" "$(norm write_file)"         "Gemini write_file → Write"
assert_eq "Write" "$(norm createFile)"         "Copilot createFile → Write"
assert_eq "Write" "$(norm save_file)"          "save_file → Write"

# --- File-edit tools → Edit ---
assert_eq "Edit" "$(norm replace)"             "Gemini replace → Edit"
assert_eq "Edit" "$(norm editFiles)"           "Copilot editFiles → Edit"
assert_eq "Edit" "$(norm edit_file)"           "edit_file → Edit"

# --- MultiEdit: any case ---
assert_eq "MultiEdit" "$(norm multiedit)"      "multiedit → MultiEdit"
assert_eq "MultiEdit" "$(norm MULTIEDIT)"      "MULTIEDIT → MultiEdit"
assert_eq "MultiEdit" "$(norm MultiEdit)"      "MultiEdit → MultiEdit"
assert_eq "MultiEdit" "$(norm mUlTiEdIt)"      "mUlTiEdIt → MultiEdit"

# --- Passthrough: canonical and unknown names unchanged ---
assert_eq "Bash" "$(norm Bash)"                "Bash passes through"
assert_eq "Edit" "$(norm Edit)"                "Edit passes through"
assert_eq "Write" "$(norm Write)"              "Write passes through"
assert_eq "apply_patch" "$(norm apply_patch)"  "apply_patch passes through"
assert_eq "some_unknown_tool" "$(norm some_unknown_tool)" "unknown passes through"
assert_eq "" "$(norm '')"                      "empty passes through"

finish_test
