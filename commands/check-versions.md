---
description: Audit dependencies against upstream registries (npm, pypi, nuget, crates.io)
---

Scans manifests under current directory and compares each dep version to the latest upstream. Reports drift without blocking.

Supported (v0.1): `package.json`, `requirements*.txt`, `pyproject.toml`, `Cargo.toml`, `*.csproj`.

Intentional pins (via `/vs-record ... "intentional: ..."`) show as `intentional-pin`, not `DRIFT`.

!bash "${CLAUDE_PLUGIN_ROOT}/scripts/check-versions.sh"

Missing or invalid required manifests require user-confirmed recovery before recreation. Do not silently recreate them. See the repository enforcement workflow in docs/enforcement.md.
