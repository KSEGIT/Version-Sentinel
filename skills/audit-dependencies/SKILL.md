---
name: audit-dependencies
description: Use when the user requests a Version Sentinel dependency audit or sees "Version Sentinel startup audit failed", missing or expired audit evidence, or an advisory startup audit warning.
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

- Report the exit status and specific diagnostic. `DRIFT`, `UNPINNED`, and `intentional-pin` rows alone do not fail the audit or authorize upgrades.
- Report completion only when the command exits 0 and explicitly reports that the online dependency audit completed. A silent exit 0 can mean the plugin is disabled; report a skipped audit truthfully.
- On failure, report registry, prerequisite, or manifest errors with the retry command. Continue the user's authorized task. A failed audit is never a permission gate.
- Preserve manifests and npm overrides when reporting parser limitations. Do not change dependencies just to make an audit pass.
- Missing or invalid manifests do not require a Version Sentinel recovery-consent ritual. Repair them only within the user's authorized scope, using repository evidence and normal rules for destructive changes.

Do not edit evidence by hand or claim a failed check passed. Rerun the audit when useful after the reported cause is resolved. Hooks always return status 0; direct audit commands may return nonzero to report validation failure or support CI.
