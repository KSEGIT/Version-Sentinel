#!/usr/bin/env bash
# Guards the plugin's install surfaces in the Claude directory.
#
# Per claude.com/docs/plugins/platform-support.md, executables in a top-level
# bin/ make Chat and Cowork refuse the whole plugin ("Can't be installed"),
# and the directory hides a listing from apps that cannot install it. A
# bin/vs-record wrapper once kept Version Sentinel out of Customize > Plugins
# on claude.ai while it was listed for Claude Code. Commands and the skill call
# scripts/vs-record.sh directly, so nothing needs bin/.
set -u
VS_TEST_NAME="directory-compat"
source "$(dirname "$0")/assert.sh"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

if [[ -e "$ROOT/bin" ]]; then
  _fail "top-level bin/ exists; Chat and Cowork refuse a plugin that ships bin/ executables"
fi

finish_test
