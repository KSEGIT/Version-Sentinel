# Version Sentinel

Claude Code plugin that hard-blocks dependency additions, bumps, and downgrades until a fresh, source-cited version check is recorded. Multi-agent: ships adapters for Claude Code (also covers z.ai GLM Coding Plan / ZCode, which reuse the Claude Code plugin format), Kimi Code, GitHub Copilot (VS Code), Gemini CLI, OpenAI Codex, and Zed.

## Project structure

```
.claude-plugin/       Plugin + marketplace metadata (plugin.json, marketplace.json)
plugin.json           Claude Code plugin manifest
hooks/hooks.json      Hook definitions, Claude Code/Codex schema (SessionStart, PreToolUse, PostToolUse)
hooks/gemini-hooks.json  Gemini CLI hook definitions (SessionStart startup, BeforeTool, AfterTool) — separate because Claude's plugin loader rejects Gemini keys in hooks/hooks.json; Gemini only auto-loads hooks/hooks.json, so point/copy this file on Gemini install (upstream: google-gemini/gemini-cli#25630)
scripts/              Bash scripts executed by hooks (prereq-check, detect-manifest-edit, detect-install-cmd, auto-record)
commands/             Slash commands: /vs-record, /check-versions (.md for Claude Code, .toml for Gemini CLI)
skills/               Skills: version-sentinel
agents/               Subagent: version-reviewer
kimi.plugin.json      Kimi Code plugin manifest
platforms/kimi/       Kimi Code adapter
gemini-extension.json Gemini CLI extension manifest
GEMINI.md             Gemini CLI auto-loaded context
.codex-plugin/        OpenAI Codex plugin metadata
.github/              GitHub Copilot hooks, agents, prompts
.agents/skills/       Cross-tool skills (Copilot, Zed, ...)
AGENTS.md             Cross-tool agent instructions
tests/                Test suite
bin/                  CLI entry points
docs/                 Documentation
```

## Supported ecosystems

- **npm** — `package.json` via registry.npmjs.org
- **pip** — `requirements*.txt`, `constraints*.txt`, `pyproject.toml` via pypi.org
- **cargo** — `Cargo.toml` via crates.io
- **dotnet** — `*.csproj`, `*.fsproj`, `*.vbproj` via api.nuget.org

## How it works

1. PreToolUse hooks intercept `Edit`/`Write`/`MultiEdit` on manifest files and `Bash` install commands
2. Hook exits 2 (blocks) if no fresh version check exists in `.version-sentinel/checks.json`
3. User runs WebSearch + `/vs-record` to record a check, then retries
4. PostToolUse hook on Bash auto-records successful install commands

The two `Bash` hooks are gated with Claude Code `if` rules (`Bash(npm *)`,
`Bash(pip *)`, ...), one per package-manager binary, so they only spawn for
package-manager commands instead of on every Bash tool call. Keyed on the
binary rather than the subcommand, so `npm i` / `npm add` / `npm install` are
all covered. `tests/test_hook_if_parity.sh` fails if a manager known to
`lib/parse-install-cmd.sh` has no matching rule — a gap there is a silent
bypass, not a slowdown.

`if` is a Claude Code field, and `.codex-plugin/plugin.json` points Codex at
this same `hooks/hooks.json`. UNVERIFIED on Codex (that platform is already
marked not-verified in docs/e2e-checklist.md). Two ways it could go wrong
there: the loader rejects the unknown `if` key and drops the hooks (the repo
has precedent — Claude Code rejected this file over Gemini keys with
`invalid_key`); or it honors `if` but its shell tool is `exec_command`, not
`Bash` (see normalize_tool_name in lib/platform.sh), so a `Bash(...)` rule
never matches. Either way the Bash guard would be off on Codex rather than
unchanged. The scripts' own early-out only covers the case where Codex ignores
`if` and still runs them. Verify on Codex before releasing.

Measured caveat: `Bash(npm *)` does not fire for `FOO=bar npm install x` or
`timeout 30 npm install x`. `lib/parse-install-cmd.sh` misses those forms too,
so behaviour is unchanged, but widening the parser requires widening the `if`
rules in the same change.

The `Edit`/`Write` hook is deliberately left ungated: it is a small share of
tool calls, and `if` matches the literal tool name, so an `Edit(...)` rule does
not fire for the `Write` tool.

## Prerequisites

- `bash`, `jq`, `curl`, `python3` (3.11+) on PATH
- Windows: Git Bash for bash/jq/curl, Python 3.13 installed separately

## Development

- Shell scripts in `scripts/` — tested via `tests/`
- State stored in `<project-root>/.version-sentinel/checks.json` (auto-gitignored)
- `VS_DISABLE=1` env var disables all hooks
