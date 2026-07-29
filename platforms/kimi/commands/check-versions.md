---
description: Audit dependencies against upstream registries (npm, pypi, nuget, crates.io)
---

Scans manifests under the current directory and compares each dependency version to the latest upstream. Reports drift without blocking.

**Usage:** `/version-sentinel:check-versions`

Supported (v0.1): `package.json`, `requirements*.txt`, `pyproject.toml`, `Cargo.toml`, `*.csproj`.

Intentional pins (recorded via `/version-sentinel:vs-record ... "intentional: ..."`) show as `intentional-pin`, not `DRIFT`.

To execute this command, run the following with your Bash tool:

    bash "$KIMI_PLUGIN_ROOT/scripts/check-versions.sh"

If `$KIMI_PLUGIN_ROOT` is not set in your shell, locate the plugin root with `/plugins info version-sentinel` (the managed copy lives under the Kimi plugins directory) and run the script from there.

Relay the script's output verbatim to the user.
