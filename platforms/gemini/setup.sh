#!/usr/bin/env bash
# Activate version-sentinel's Gemini CLI hooks inside an *installed* extension copy.
#
# Why this exists: Gemini CLI only auto-discovers hooks at <extension>/hooks/hooks.json,
# but this repo's hooks/hooks.json uses the Claude Code / Codex schema, and Claude Code
# hard-rejects Gemini event keys (BeforeTool/AfterTool). One path can't serve both hosts.
# Gemini CLI copies (clones) the repo on `gemini extensions install`, so overwriting
# hooks/hooks.json inside the *installed copy* is safe and does not affect the repo.
#
# Usage:
#   gemini extensions install https://github.com/KSEGIT/Version-Sentinel
#   bash ~/.gemini/extensions/version-sentinel/platforms/gemini/setup.sh
#   # restart gemini
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

# Safety: refuse to run inside a source checkout of the repo (would break Claude/Codex hooks).
# Require ROOT to exactly match the canonical Gemini extension directory.
GEMINI_HOME="${GEMINI_HOME:-$HOME/.gemini}"
EXPECTED_ROOT="$GEMINI_HOME/extensions/version-sentinel"
EXPECTED_ROOT="$(cd "$GEMINI_HOME/extensions" 2>/dev/null && pwd)/version-sentinel" || EXPECTED_ROOT="$GEMINI_HOME/extensions/version-sentinel"

if [[ "$ROOT" != "$EXPECTED_ROOT" ]]; then
  echo "version-sentinel: refusing to activate Gemini hooks outside a Gemini extension install." >&2
  echo "  expected: $EXPECTED_ROOT" >&2
  echo "  got:      $ROOT" >&2
  echo "  install first: gemini extensions install https://github.com/KSEGIT/Version-Sentinel" >&2
  exit 1
fi

cp "$ROOT/hooks/gemini-hooks.json" "$ROOT/hooks/hooks.json"
echo "version-sentinel: Gemini hooks activated at $ROOT/hooks/hooks.json"
echo "Restart gemini to load them."
