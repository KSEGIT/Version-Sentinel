---
name: vs-refresh
description: Use when the user invokes /vs-refresh or asks Version Sentinel to refresh project audit or security evidence.
---

Run the online Version Sentinel audit for the affected project. It checks declared versions and runs the configured security checks where applicable.

Locate the bundled script relative to this skill directory. Use `../../scripts/vs-refresh.sh` in an installed plugin or `../../../scripts/vs-refresh.sh` in the repository's `.agents/skills/` copy. For a standalone copy of the skill, locate the installed Version Sentinel plugin and its bundled script. Keep the affected project as the working directory.

```bash
cd "<project-directory>" && bash "<absolute-version-sentinel-root>/scripts/vs-refresh.sh"
```

Report the exit status, findings, and the project audit expiry if it was printed. A silent or skipped run has no new evidence. A failed refresh is advisory. Continue authorized work. Individual package checks use `vs-record`.
