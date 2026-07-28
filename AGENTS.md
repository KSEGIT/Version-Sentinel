# Version Sentinel — Cross-Agent Instructions

Version Sentinel is a guardrail that prevents stale, hallucinated, or compromised dependency versions from reaching your manifests. Before any dependency is added, bumped, downgraded, or installed, the agent must verify the intended version against its upstream registry and record that check. Checks are stored in `.version-sentinel/checks.json` and expire after a freshness window (default 24h).

## Required workflow when a dependency change is blocked

If a hook blocks an edit or install (exit 2, `BLOCKED: version-sentinel`), or if you are about to change any dependency on a platform without hooks:

1. **Look up the latest version on the upstream registry** via web search or fetch:
   - npm: `https://www.npmjs.com/package/<pkg>`
   - pip / pyproject: `https://pypi.org/project/<pkg>/`
   - cargo: `https://crates.io/crates/<pkg>`
   - csproj (NuGet): `https://www.nuget.org/packages/<pkg>`
2. **Record the check:**

   ```bash
   bash scripts/vs-record.sh <ecosystem> <pkg> <version> <source-url-or-intentional:reason>
   ```

   The source must be an `http(s)://` URL you actually consulted, or `intentional:<reason>` for deliberate pins (e.g. CVE lock, compatibility). Example:

   ```bash
   bash scripts/vs-record.sh npm lodash 4.17.21 https://www.npmjs.com/package/lodash
   bash scripts/vs-record.sh csproj Serilog 3.1.1 "intentional: CVE lock pending audit"
   ```

3. **Retry the edit or install.** With a fresh entry on record, the hook (where present) lets the operation through.

Never fabricate a source URL you did not actually consult, and never bypass the record step to force a dependency change through.

## Audit

```bash
bash scripts/check-versions.sh
```

Scans manifests within 4 directory levels of the current directory, compares each dependency against its upstream registry, and reports drift. Intentional pins show as `intentional-pin`, not `DRIFT`. Run before tagging a release.

## Supported manifests

`package.json` (npm/pnpm/yarn/bun), `requirements*.txt`, `constraints*.txt`, `pyproject.toml` (pip, Poetry, uv), `Cargo.toml`, and `*.csproj` / `*.fsproj` / `*.vbproj` (NuGet).

## Escape hatch

`VS_DISABLE=1` makes all hooks no-op (block, prereq warning, auto-record). Use only for throwaway sessions; do not set it without the user's awareness.

## Platform behavior

- On platforms with hooks (Claude Code and derivatives such as z.ai's ZCode / GLM Coding Plan, Kimi Code, OpenAI Codex), the workflow above is **enforced automatically** via PreToolUse hooks.
- On platforms without hooks (e.g. Zed), you MUST follow the same workflow **voluntarily** before any dependency change: look up the version, run `bash scripts/vs-record.sh ...`, then make the edit.

## Project structure

- `plugin.json`, `.claude-plugin/` — Claude Code plugin manifest and metadata.
- `kimi.plugin.json` — Kimi Code plugin manifest (root); `kimi-marketplace.json` — Kimi marketplace catalog.
- `gemini-extension.json`, `GEMINI.md` — Gemini CLI extension manifest and context; `hooks/gemini-hooks.json` + `platforms/gemini/setup.sh` — Gemini hook wiring.
- `.codex-plugin/plugin.json` — OpenAI Codex plugin manifest (reuses `hooks/hooks.json`).
- `.github/` — GitHub Copilot: `hooks/`, `agents/`, `prompts/`, `copilot-instructions.md`.
- `.agents/skills/` — cross-tool skills (Copilot, Zed, Codex).
- `AGENTS.md` — this file; read automatically by Codex, Zed, and GitHub Copilot.
- `scripts/` — hook and workflow scripts (`vs-record.sh`, `check-versions.sh`, `detect-manifest-edit.sh`, `detect-install-cmd.sh`, `auto-record.sh`, `prereq-check.sh`).
- `commands/` — Claude Code slash commands (`/vs-record`, `/check-versions`).
- `platforms/kimi/commands/` — Kimi Code command files (same workflow, `$KIMI_PLUGIN_ROOT`-based).
- `skills/version-sentinel/` — agent skill explaining how to satisfy the hook.
- `hooks/hooks.json` — hook definitions (Claude Code / Codex schema).
- `tests/` — shell test suite; run `tests/run.sh`.
