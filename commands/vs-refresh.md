---
description: Refresh Version Sentinel project audit and security evidence
---

Use the affected project as the Bash working directory. Run the refresh script from the installed plugin.

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/vs-refresh.sh"
```

Report the exit status, findings, and the project audit expiry if it was printed. Report a skipped or failed audit as such. Keep the user's authorized work moving. Use `/version-sentinel:vs-record` to record an individual package check.
