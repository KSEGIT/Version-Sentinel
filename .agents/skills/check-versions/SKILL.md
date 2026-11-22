---
name: check-versions
description: Use when the user invokes /check-versions or asks to compare a project's dependency versions against upstream registries with Version Sentinel.
---

Run the online Version Sentinel audit from the affected project. The audit records project evidence and runs the configured security checks where applicable.

Locate the bundled script relative to this skill directory. Use `../../scripts/check-versions.sh` in an installed plugin or `../../../scripts/check-versions.sh` in the repository's `.agents/skills/` copy. For a standalone copy of the skill, locate the installed Version Sentinel plugin and its bundled script. Keep the affected project as the working directory.

```bash
cd "<project-directory>" && bash "<absolute-version-sentinel-root>/scripts/check-versions.sh"
```

Report the exit status, drift, and findings. A silent exit 0 can mean the audit was skipped. Registry, prerequisite, and manifest errors are advisory. Continue authorized work and preserve the project's dependency versions. Use `vs-refresh` when the user also wants the audit's expiry.
