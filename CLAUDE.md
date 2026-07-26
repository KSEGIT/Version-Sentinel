# Version Sentinel

Claude Code plugin that hard-blocks dependency additions, bumps, and downgrades until a fresh, source-cited version check is recorded. Multi-agent: ships adapters for Claude Code, Kimi Code, GitHub Copilot (VS Code), Gemini CLI, OpenAI Codex, and Zed.

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

## Prerequisites

- `bash`, `jq`, `curl`, `python3` (3.11+) on PATH
- Windows: Git Bash for bash/jq/curl, Python 3.13 installed separately

## Development

- Shell scripts in `scripts/` — tested via `tests/`
- State stored in `<project-root>/.version-sentinel/checks.json` (auto-gitignored)
- `VS_DISABLE=1` env var disables all hooks
