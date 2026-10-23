#!/usr/bin/env bash
# Guards the plugin's install surfaces in the Claude directory.
#
# Per claude.com/docs/plugins/platform-support.md, executables in a top-level
# bin/ make Chat and Cowork refuse the whole plugin ("Can't be installed").
# Version Sentinel was absent from Customize > Plugins on claude.ai, but the
# cause of that listing issue has not been confirmed. Commands and the skill
# call scripts/vs-record.sh directly, so nothing needs bin/.
set -u
VS_TEST_NAME="directory-compat"
source "$(dirname "$0")/assert.sh"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

if [[ -e "$ROOT/bin" ]]; then
  _fail "top-level bin/ exists; Chat and Cowork refuse a plugin that ships bin/ executables"
fi

finish_test
