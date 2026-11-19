---
description: Audit dependencies against upstream registries (npm, pypi, nuget, crates.io)
---

From the user's project directory, run the bundled online audit below. It records current audit evidence without changing dependency versions. Use it after a "Version Sentinel startup audit failed" warning or when audit evidence is missing or expired. The `audit-dependencies` skill provides the same workflow.

Supported: `package.json`, `requirements*.txt`, `constraints*.txt`, `pyproject.toml`, `Cargo.toml`, `*.csproj`, `*.fsproj`, and `*.vbproj`.

Intentional pins (via `/vs-record ... "intentional: ..."`) show as `intentional-pin`, not `DRIFT`.

!bash "${CLAUDE_PLUGIN_ROOT}/scripts/check-versions.sh"

Report the exit status and full diagnostic. Drift alone does not fail the audit. Registry, prerequisite, and manifest errors are advisory: continue authorized work and report the limitation. Preserve npm overrides and other selectors. Do not change dependencies to make the audit pass. No Version Sentinel recovery-consent command is needed; normal authorization rules for destructive changes still apply separately.
