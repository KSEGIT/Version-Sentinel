# Version Sentinel in Zed

Zed has **no hook mechanism** for agent tool calls — the upstream PR adding hooks was closed unmerged (as of mid-2026). That means version-sentinel's signature feature, *automatically blocking a dependency edit or install until a version check is recorded*, **cannot work on Zed**. What follows is the best-effort approximation and how to set it up.

## What works

- **`AGENTS.md` workflow instructions.** Zed automatically reads the project `AGENTS.md` into the agent's context. It documents the version-sentinel workflow (verify → record → proceed) so the agent follows it voluntarily.
- **`.agents/skills/version-sentinel/SKILL.md`.** Zed discovers skills from `.agents/skills/<name>/SKILL.md`. The version-sentinel skill tells the agent the full verify-and-record flow whenever it touches a dependency manifest.
- **The scripts themselves.** Everything runs fine from Zed's terminal tool:
  - `bash scripts/vs-record.sh <ecosystem> <pkg> <version> <source-url-or-intentional:>` — record a verified check into `.version-sentinel/checks.json`.
  - `bash scripts/check-versions.sh` — audit all manifests against upstream registries.

## What doesn't work

- **No automatic blocking.** There are no PreToolUse/PostToolUse hooks in Zed, so nothing intercepts an edit to `package.json` or an `npm install` before it happens. The workflow is advisory, not enforced.
- **No stateful "block until check recorded."** The static rules below prompt for confirmation *every time* a matching command or path appears — they cannot check `.version-sentinel/checks.json` for a fresh record and auto-approve. Expect repeated confirmations; that's the price of a static approximation.

## Static approximation: `.zed/settings.json`

Zed's `agent.tool_permissions` can force a confirmation prompt on matching terminal commands and file edits. Paste this into your project `.zed/settings.json` (merge with existing settings):

```json
{
  "agent": {
    "tool_permissions": {
      "tools": {
        "terminal": {
          "always_confirm": [
            {
              "pattern": "\\b(npm|pnpm|yarn|bun)\\s+(install|add|i)\\b"
            },
            {
              "pattern": "\\bpip\\s+install\\b"
            },
            {
              "pattern": "\\bcargo\\s+add\\b"
            },
            {
              "pattern": "\\bdotnet\\s+add\\s+package\\b"
            }
          ]
        },
        "edit_file": {
          "always_confirm": [
            {
              "pattern": "package\\.json$"
            },
            {
              "pattern": "requirements.*\\.txt$"
            },
            {
              "pattern": "pyproject\\.toml$"
            },
            {
              "pattern": "Cargo\\.toml$"
            },
            {
              "pattern": "\\.csproj$"
            },
            {
              "pattern": "\\.fsproj$"
            },
            {
              "pattern": "\\.vbproj$"
            }
          ]
        }
      }
    }
  }
}
```

**How to read this:** every matching install command or manifest edit triggers a confirmation prompt. At that prompt, you (or the agent, per the skill instructions) should first verify the version on the upstream registry (npmjs.com / pypi.org / crates.io / nuget.org) and record it with `bash scripts/vs-record.sh ...`, then approve. These are **unconditional prompts, not stateful blocking** — they fire even when a valid check is already recorded.

## Recommended Zed flow

1. Let `AGENTS.md` + the skill instruct the agent on the workflow.
2. Use the `always_confirm` rules above as a tripwire for manifests and installs.
3. Before releases, run `bash scripts/check-versions.sh` (or ask the agent to) to audit drift; `intentional:` pins show as `intentional-pin`, not `DRIFT`.

If Zed lands a real hook API in the future, this document should be revisited to wire `scripts/detect-manifest-edit.sh` / `scripts/detect-install-cmd.sh` in as true blocking hooks.
