# Version Sentinel

Claude Code plugin that hard-blocks dependency additions, bumps, and downgrades until a fresh, source-cited version check is recorded.

## Project structure

```
.claude-plugin/       Plugin + marketplace metadata (plugin.json, marketplace.json)
hooks/hooks.json      Hook definitions (SessionStart, PreToolUse, PostToolUse)
scripts/              Bash scripts executed by hooks (prereq-check, detect-manifest-edit, detect-install-cmd, auto-record)
commands/             Slash commands: /vs-record, /check-versions
skills/               Skills: version-sentinel, vs-record, check-versions
agents/               Subagent: version-reviewer
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
