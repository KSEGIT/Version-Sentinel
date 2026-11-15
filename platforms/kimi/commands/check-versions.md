---
description: Audit dependencies against upstream registries (npm, pypi, nuget, crates.io)
---

From the user's project directory, run the bundled online audit. It records current audit evidence without changing dependency versions. Use it after a "Version Sentinel startup audit failed" warning or when audit evidence is missing or expired. The `audit-dependencies` skill provides the same workflow.

**Usage:** `/version-sentinel:check-versions`

Supported: `package.json`, `requirements*.txt`, `constraints*.txt`, `pyproject.toml`, `Cargo.toml`, `*.csproj`, `*.fsproj`, and `*.vbproj`.

Intentional pins (recorded via `/version-sentinel:vs-record ... "intentional: ..."`) show as `intentional-pin`, not `DRIFT`.

To execute this command, run the following with your Bash tool:

    bash "$KIMI_PLUGIN_ROOT/scripts/check-versions.sh"

If `$KIMI_PLUGIN_ROOT` is not set in your shell, locate the plugin root with `/plugins info version-sentinel` (the managed copy lives under the Kimi plugins directory) and run the script from there.

Relay the script's output and exit status to the user. Drift alone does not fail the audit. Registry or manifest errors leave dependency work blocked; resolve the reported cause and rerun. Preserve npm overrides and report parser limitations as tool limitations. Do not change dependencies or disable enforcement to pass the audit.

Missing or invalid required manifests require user-confirmed recovery before recreation. Do not silently recreate them. See the repository enforcement workflow in docs/enforcement.md.
