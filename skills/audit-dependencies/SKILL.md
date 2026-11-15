---
name: audit-dependencies
description: Use when the user requests a Version Sentinel dependency audit or sees "Version Sentinel startup audit failed", missing or expired audit evidence, or dependency work blocked by the startup audit.
---

# Audit dependencies

Run the online audit for the user's current project and report the result. The audit records evidence in `.version-sentinel/audit.json`; it does not install packages or change dependency versions.

## Run the audit

1. Use the project directory named in the startup warning or the user's request. Keep that directory as the command's working directory; do not audit the plugin installation.
2. Locate the script bundled with **this skill**. In a plugin install it is `../../scripts/check-versions.sh` relative to this skill's directory. In the repository's `.agents/skills/` copy it is `../../../scripts/check-versions.sh`. Resolve the script to an absolute path. Do not select an older `./scripts/check-versions.sh` just because it exists in the user's project, or assume plugin environment variables are set in the terminal.
3. Run through Bash, quoting both paths:

   ```bash
   cd "<project-directory>" && bash "<absolute-plugin-root>/scripts/check-versions.sh"
   ```

   Inside Codex, the script reads `CODEX_THREAD_ID` automatically. Keep the current session identity; do not invent one or copy audit evidence from another project.

## Report the result

- Report the exit status and the specific diagnostic. `DRIFT`, `UNPINNED`, and `intentional-pin` rows alone do not fail the audit or authorize upgrades.
- Report completion only when the command exits 0 and prints `mandatory online dependency audit completed`. A silent exit 0 can mean the plugin is disabled; report that the audit was skipped, without changing the disable setting or claiming current evidence. Separate package-version recording is still required before dependency changes.
- On failure, keep dependency work blocked. Report registry or prerequisite failures with the retry command. For parser limitations, preserve manifests and npm overrides and report the tool limitation. Missing or invalid manifests need the user's approval before repair or recreation.

Do not disable hooks, bypass verification, edit evidence by hand, or change dependencies to make the audit pass. After the reported cause is resolved, rerun this same command.
