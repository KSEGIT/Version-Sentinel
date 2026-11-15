---
description: Audit dependencies against upstream registries (npm, pypi, nuget, crates.io)
---

From the user's project directory, run the bundled online audit below. It records current audit evidence without changing dependency versions. Use it after a "Version Sentinel startup audit failed" warning or when audit evidence is missing or expired. The `audit-dependencies` skill provides the same workflow.

Supported: `package.json`, `requirements*.txt`, `constraints*.txt`, `pyproject.toml`, `Cargo.toml`, `*.csproj`, `*.fsproj`, and `*.vbproj`.

Intentional pins (via `/vs-record ... "intentional: ..."`) show as `intentional-pin`, not `DRIFT`.

!bash "${CLAUDE_PLUGIN_ROOT}/scripts/check-versions.sh"

Report the exit status and full failure diagnostic. Drift alone does not fail the audit. Registry or manifest errors leave dependency work blocked; resolve the reported cause and rerun. Preserve npm overrides and report parser limitations as tool limitations. Do not change dependencies or disable enforcement to pass the audit.

Missing or invalid required manifests require user-confirmed recovery before recreation. Do not silently recreate them. See the repository enforcement workflow in docs/enforcement.md.
