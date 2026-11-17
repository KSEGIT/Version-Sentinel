---
description: Audit dependencies against upstream registries (npm, pypi, nuget, crates.io)
---

From the user's project directory, run the bundled online audit. It records current audit evidence without changing dependency versions. Use it after a "Version Sentinel startup audit failed" warning or when audit evidence is missing or expired. The `audit-dependencies` skill provides the same workflow.

**Usage:** `/version-sentinel:check-versions`

Supported: `package.json`, `requirements*.txt`, `constraints*.txt`, `pyproject.toml`, `Cargo.toml`, `*.csproj`, `*.fsproj`, and `*.vbproj`.

Intentional pins (recorded via `/version-sentinel:vs-record ... "intentional: ..."`) show as `intentional-pin`, not `DRIFT`.

To execute this command, run the following with your Bash tool:

    bash "$KIMI_PLUGIN_ROOT/scripts/check-versions.sh"

If `$KIMI_PLUGIN_ROOT` is not set in your shell, locate the plugin root with `/plugins info version-sentinel` (the managed copy lives under the Kimi plugins directory). Resolve its `scripts/check-versions.sh` to an absolute path, then run that path with Bash while keeping the affected project as the working directory. Use the project named in the startup warning, or the user's current project if there is no warning; do not change directory to the plugin installation.

Report the exit status and full diagnostic. Drift alone does not fail the audit. Registry, prerequisite, and manifest errors are advisory: continue authorized work and report the limitation. Preserve npm overrides and other selectors. Do not change dependencies to make the audit pass. No Version Sentinel recovery-consent command is needed; normal authorization rules for destructive changes still apply separately.
