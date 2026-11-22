---
description: Refresh Version Sentinel project audit and security evidence
agent: agent
---

Use the terminal from the affected project directory. Resolve the installed Version Sentinel root, or use the root of the Version Sentinel source checkout that supplied this prompt. Use the absolute path to its bundled script.

```bash
bash "<absolute-version-sentinel-root>/scripts/vs-refresh.sh"
```

Report the exit status, findings, and the project audit expiry if it was printed. Report a skipped or failed audit as such. Keep the user's authorized work moving. Use `/vs-record` to record an individual package check.
