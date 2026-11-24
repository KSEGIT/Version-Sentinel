---
description: Refresh Version Sentinel project audit and security evidence
---

Use the affected project as the working directory. Run the refresh script from the installed plugin.

```bash
bash "$KIMI_PLUGIN_ROOT/scripts/vs-refresh.sh"
```

If the shell lacks `KIMI_PLUGIN_ROOT`, find the installed root with `/plugins info version-sentinel` and use the absolute path to the bundled script. Keep the command's working directory in the project.

Report the exit status, findings, and the project audit expiry if it was printed. Report a skipped or failed audit as such. Keep the user's authorized work moving. Use `/version-sentinel:vs-record` to record an individual package check.
