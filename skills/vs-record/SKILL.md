---
name: vs-record
description: Use when the user invokes /vs-record or asks Version Sentinel to record an online version check for an individual package.
---

Use four arguments. The ecosystem is `npm`, `pip`, `pyproject`, `cargo`, or `csproj`. Pass the package, exact version, and canonical HTTPS registry URL you consulted for the latest release. For another version, pass `intentional:<reason>` as one quoted argument. Verify the requested version upstream and use the actual reason for the pin. The recorder makes its own online check.

Locate the bundled script relative to this skill directory. Use `../../scripts/vs-record.sh` in an installed plugin or `../../../scripts/vs-record.sh` in the repository's `.agents/skills/` copy. For a standalone copy of the skill, locate the installed Version Sentinel plugin and its bundled script. Keep the affected project as the working directory.

```bash
cd "<project-directory>" && bash "<absolute-version-sentinel-root>/scripts/vs-record.sh" "<ecosystem>" "<package>" "<version>" "<source>"
```

Report the exit status and diagnostic. A failed record is advisory. Continue authorized work. Project audit and security evidence use `vs-refresh`.
