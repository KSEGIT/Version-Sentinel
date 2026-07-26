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
case "$ROOT" in
  *".gemini/extensions/"*) : ;;
  *)
    echo "version-sentinel: refusing to activate Gemini hooks outside a Gemini extension install." >&2
    echo "  expected path under ~/.gemini/extensions/, got: $ROOT" >&2
    echo "  install first: gemini extensions install https://github.com/KSEGIT/Version-Sentinel" >&2
    exit 1
    ;;
esac

cp "$ROOT/hooks/gemini-hooks.json" "$ROOT/hooks/hooks.json"
echo "version-sentinel: Gemini hooks activated at $ROOT/hooks/hooks.json"
echo "Restart gemini to load them."
