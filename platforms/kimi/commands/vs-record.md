---
description: Record a fresh version check in the version-sentinel sidecar
---

Record that a dependency version has been verified. Run after a web search/fetch (or docs lookup) confirms the version.

**Usage:** `/version-sentinel:vs-record <ecosystem> <pkg> <version> <source>`

**Source** must be an `http(s)://` URL or `intentional:<reason>`.

**Ecosystems (v0.1):** npm, pip, cargo, csproj, pyproject

**Examples:**
- `/version-sentinel:vs-record npm lodash 4.17.21 https://www.npmjs.com/package/lodash`
- `/version-sentinel:vs-record pip requests 2.31.0 https://pypi.org/project/requests/`
- `/version-sentinel:vs-record csproj Serilog 3.1.1 intentional: CVE lock pending audit`

To execute this command, run the following with your Bash tool, passing the user's arguments through as-is:

    bash "$KIMI_PLUGIN_ROOT/scripts/vs-record.sh" $ARGUMENTS

If `$KIMI_PLUGIN_ROOT` is not set in your shell, locate the plugin root with `/plugins info version-sentinel` (the managed copy lives under the Kimi plugins directory) and run the script from there.

Relay the script's output verbatim to the user. If it exits non-zero, report the error and do not retry with fabricated values.
