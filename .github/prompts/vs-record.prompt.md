---
description: Record a fresh version check in the version-sentinel sidecar
agent: agent
argument-hint: <ecosystem> <pkg> <version> <source-url-or-intentional:>
---

Record that a dependency version has been verified. Run after a web search or registry fetch confirms the version.

**Usage:** `/vs-record <ecosystem> <pkg> <version> <source>`

**Source** must be an `http(s)://` URL or `intentional:<reason>`.

**Ecosystems (v0.1):** npm, pip, cargo, csproj, pyproject

**Examples:**
- `/vs-record npm lodash 4.17.21 https://www.npmjs.com/package/lodash`
- `/vs-record pip requests 2.31.0 https://pypi.org/project/requests/`
- `/vs-record csproj Serilog 3.1.1 intentional: CVE lock pending audit`

Use the terminal tool to run `bash scripts/vs-record.sh` with the arguments the user supplied, exactly as given. Relay the script's output verbatim to the user. If the script fails, show its stderr and do not retry with modified arguments unless the user asks.
