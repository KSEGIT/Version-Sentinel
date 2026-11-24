# Advisory dependency checks

Version Sentinel warns about dependency evidence. It never blocks tools or instructs an agent to pause the user's task. All hook entrypoints return status 0, including startup errors, parser errors, missing prerequisites, unsupported selectors, stale evidence, and missing or invalid manifests. Gemini and Copilot adapters also allow the call; diagnostics are advisory context.

## Recommended workflow

Use `/vs-refresh` to refresh project audit evidence and run the configured security checks. The command prints the saved project audit timestamp and its expiry in UTC. It uses `VS_WINDOW_HOURS` or `CLAUDE_PLUGIN_OPTION_WINDOW_HOURS` when the shell has it, with a default of 24 hours. Security checks apply their own settings and save separate evidence. `/check-versions` remains available for the standard audit report. `/vs-record` checks one package version. [Host command names](../README.md#commands)

For terminal use, keep the affected project as the working directory and run the bundled scripts by absolute path.

```bash
bash <plugin-root>/scripts/vs-refresh.sh
bash <plugin-root>/scripts/vs-record.sh npm lodash 4.17.21 'intentional: compatibility with the current application'
```

An audit compares declared versions with public upstream releases. `DRIFT` reports a newer release without changing dependencies. The recorder makes its own HTTPS upstream request to verify the intended version exists. Older pins need a reason for a successful record. Failed lookups, URL-only legacy records, offline cache, and post-install records must not be presented as successful online checks. Private registries are outside this verifier's scope.

Use `/vs-refresh` after a startup warning when useful. Report the exit status and diagnostics. The optional refresh only reports new evidence after a successful audit. Continue authorized work after any result.

Direct audit, recorder, and validation commands can return nonzero to report invalid data, missing manifests, or failed registry requests. CI may use that status. Hook adapters report such findings as warnings and always allow the tool call.

## Evidence and scan scope

Package checks live in `.version-sentinel/checks.json`, project audit state in `audit.json`, and security findings in `security.json`. Fresh project audit evidence applies across sessions when the canonical project path and dependency files match. The state keeps the session ID for reference when available. Fresh package checks can be reused for the same project, package, and version during the configured window.

Tool hooks keep a local warning history. A project and each worktree get their own history. A warning can return when the files, evidence, settings, or diagnostic change, or after a successful check. Hooks also show warnings when they cannot read or save warning history. The history supplies no audit or package evidence.

Discovery covers four directory levels and excludes generated/vendor/state directories such as `.git`, `.worktrees`, `node_modules`, `target`, `.venv`, `venv`, `.version-sentinel`, and `__pycache__`. Supported requirements includes can extend beyond discovery depth, within the canonical project root. Deeper unreferenced projects need their own audit for complete reporting. Startup gives optional audit guidance without scanning manifests or contacting registries. A direct audit reports when it finds no supported manifest.

Local paths, URLs, git/workspace sources, NuGet Central Package Management, private registries, some overrides/catalogues, and dynamic shell forms cannot all be verified. Audit reports do not resolve every range, transitive lockfile version, platform marker, or vulnerability. Preserve manifest contents and report parser limitations as tool limitations. Do not remove overrides or change dependencies just to satisfy the parser.

## Missing or invalid manifests

Report the finding and inspect repository evidence. Continue repairs already authorized by the user's task. Version Sentinel does not require a recovery-consent command, and its warnings do not require a new approval request. Ordinary authorization rules still apply to destructive reconstruction or changes outside the task. Never guess dependency contents or claim an invalid manifest passed the audit.

## Platform setup

Claude Code, Codex, Kimi, Gemini, and Copilot adapters use the same advisory policy. Hosts without hooks use the recommended checks manually. `VS_DISABLE=1` suppresses hook warnings; it is not needed to continue work.

Updating source does not reload an installed plugin or change an existing session. Use the normal plugin update path and host trust settings, then start a new session to test advisory behavior. Do not modify installed caches to simulate activation. The hooks are diagnostics, not an operating-system sandbox or a vulnerability scanner.

## npm security diagnostics

Explicit audits use npm audit and OSV by default for public npm lockfile v2/v3 projects. Each provider can be disabled separately with the `security_npm_audit` or `security_osv` plugin setting, or `VS_SECURITY_NPM_AUDIT=0` or `VS_SECURITY_OSV=0`. Findings retain provider attribution, severity, advisory IDs, and links. Missing, stale, or incomplete evidence is reported truthfully.

Public tool hooks only check local cached security evidence. They make no provider requests and do not launch the saved-settings CLI. A proposed change can produce a warning even when the resolved tree has current evidence. Use `/vs-refresh` after dependency changes to audit the resolved tree with the configured security checks. Low and moderate findings remain visible as advisory text.

The explicit `reconcile-npm-lock.sh` helper can regenerate a lockfile without install scripts and scan it before replacement. Its Git/project/settings evidence and validation errors apply to that explicit command, not permission to continue other work. See [the privacy policy](https://github.com/KSEGIT/Version-Sentinel/blob/main/PRIVACY.md) for upstream package-name disclosures and local evidence storage.

## Optional cleanup of a manifest deleted in Git

An explicit audit can retain a required-path entry after a deliberate committed deletion. The optional `retire-manifest.sh` command removes that stale audit entry and saves a receipt. It is not needed to continue dependency work.

When the user has authorized that metadata cleanup, run from the affected project:

```bash
bash <plugin-root>/scripts/retire-manifest.sh path/to/requirements-old.txt --deleted-by FULL_COMMIT_ID --user-confirmed 'Actual user-approved reason'
```

The flag records an attestation of actual consent; it does not obtain consent. The command verifies an exact regular-file deletion by a single-parent ancestor Git commit, absence from HEAD/index/working tree, and that no live include or lockfile still requires the manifest. It rejects forged ancestry and unproven deletions. It removes only that stale entry, records Git/content/reason details, and invalidates audit evidence. Recreated manifests are discovered normally. A transaction lock preserves receipts and required paths across concurrent audit updates. Explicit audit failures remain truthful diagnostics, and public hooks continue to warn and allow work.
