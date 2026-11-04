---
description: Audit dependencies against upstream registries (npm, pypi, nuget, crates.io)
agent: agent
---

Use the terminal tool to run `bash scripts/check-versions.sh` in the workspace root. It scans manifests under the current directory and compares each dependency version to the latest upstream. Supported (v0.1): `package.json`, `requirements*.txt`, `pyproject.toml`, `Cargo.toml`, `*.csproj`.

Relay the full output to the user, then interpret it briefly:

- **DRIFT** rows: current ≠ latest with no `intentional:` record. Suggest looking up the latest version and recording it with `bash scripts/vs-record.sh <ecosystem> <pkg> <version> <source-url>` before bumping.
- **intentional-pin** rows: deliberate pins with a recorded reason — no action needed unless the pin is stale.
- **lookup-failed** rows: registry fetch failed; suggest re-running once, then checking the registry URL manually.

Version drift alone is advisory. A missing, failed, expired, or outdated audit blocks dependency work.

Missing or invalid required manifests require user-confirmed recovery before recreation. Do not silently recreate them. See the repository enforcement workflow in docs/enforcement.md.
