---
description: Record a fresh version check in the version-sentinel sidecar
argument-hint: <ecosystem> <pkg> <version> <source-url-or-intentional:>
---

Record that a dependency version has been verified. Run after WebSearch/WebFetch/context7 confirms the version.

**Usage:** `/vs-record <ecosystem> <pkg> <version> <source>`

**Source** must be `http(s)://` URL or `intentional:<reason>`.

**Ecosystems (v0.1):** npm, pip, cargo, csproj, pyproject

**Examples:**
- `/vs-record npm lodash 4.17.21 https://www.npmjs.com/package/lodash`
- `/vs-record pip requests 2.31.0 https://pypi.org/project/requests/`
- `/vs-record csproj Serilog 3.1.1 intentional: CVE lock pending audit`

!bash ${CLAUDE_PLUGIN_ROOT}/scripts/vs-record.sh $ARGUMENTS
