#!/usr/bin/env bash
# Tests scripts/lib/options.sh: CLAUDE_PLUGIN_OPTION_* → legacy VS_* mapping.
set -u
VS_TEST_NAME="options-lib"
source "$(dirname "$0")/assert.sh"

LIB="$(cd "$(dirname "$0")/.." && pwd)/scripts/lib/options.sh"

# Helper: run a fresh subshell with a controlled env, source the lib, echo target var.
# Usage: run_case "<env assignments>" "<var-to-echo>"
run_case() {
  local env_str="$1" var="$2"
  # Use env -i to strip inherited env, but keep PATH so bash finds builtins/utilities.
  env -i PATH="$PATH" HOME="$HOME" bash -c "
    set -u
    $env_str
    source '$LIB'
    # Echo the requested var; if unset, print UNSET.
    if [[ -z \"\${$var+x}\" ]]; then
      echo UNSET
    else
      echo \"\${$var}\"
    fi
  "
}

# --- VS_DISABLE mapping from CLAUDE_PLUGIN_OPTION_DISABLE ---
assert_eq "1" "$(run_case 'export CLAUDE_PLUGIN_OPTION_DISABLE=true' VS_DISABLE)" "DISABLE=true → VS_DISABLE=1"
assert_eq "1" "$(run_case 'export CLAUDE_PLUGIN_OPTION_DISABLE=1'    VS_DISABLE)" "DISABLE=1 → VS_DISABLE=1"
assert_eq "1" "$(run_case 'export CLAUDE_PLUGIN_OPTION_DISABLE=TRUE' VS_DISABLE)" "DISABLE=TRUE → VS_DISABLE=1"
assert_eq "1" "$(run_case 'export CLAUDE_PLUGIN_OPTION_DISABLE=True' VS_DISABLE)" "DISABLE=True → VS_DISABLE=1"
assert_eq "0" "$(run_case 'export CLAUDE_PLUGIN_OPTION_DISABLE=false' VS_DISABLE)" "DISABLE=false → VS_DISABLE=0"
assert_eq "0" "$(run_case 'export CLAUDE_PLUGIN_OPTION_DISABLE=bogus' VS_DISABLE)" "DISABLE=bogus → VS_DISABLE=0"
assert_eq "0" "$(run_case 'export CLAUDE_PLUGIN_OPTION_DISABLE='      VS_DISABLE)" "DISABLE='' → VS_DISABLE=0"
assert_eq "0" "$(run_case ':' VS_DISABLE)" "DISABLE unset → VS_DISABLE=0"

# User-set VS_DISABLE wins over CLAUDE_PLUGIN_OPTION_DISABLE
assert_eq "1" "$(run_case 'export VS_DISABLE=1; export CLAUDE_PLUGIN_OPTION_DISABLE=false' VS_DISABLE)" \
  "user VS_DISABLE=1 beats DISABLE=false"

# --- VS_WINDOW_HOURS mapping from CLAUDE_PLUGIN_OPTION_WINDOW_HOURS ---
assert_eq "48" "$(run_case 'export CLAUDE_PLUGIN_OPTION_WINDOW_HOURS=48' VS_WINDOW_HOURS)" \
  "WINDOW_HOURS=48 → VS_WINDOW_HOURS=48"
assert_eq "UNSET" "$(run_case ':' VS_WINDOW_HOURS)" \
  "WINDOW_HOURS unset → VS_WINDOW_HOURS not set"
assert_eq "72" "$(run_case 'export VS_WINDOW_HOURS=72; export CLAUDE_PLUGIN_OPTION_WINDOW_HOURS=48' VS_WINDOW_HOURS)" \
  "user VS_WINDOW_HOURS=72 beats WINDOW_HOURS=48"

finish_test
