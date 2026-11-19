# Advisory dependency checks

Version Sentinel warns about dependency evidence. It never blocks tools or instructs an agent to pause the user's task. All hook entrypoints return status 0, including startup errors, parser errors, missing prerequisites, unsupported selectors, stale evidence, and missing or invalid manifests. Gemini and Copilot adapters also allow the call; diagnostics are advisory context.

## Recommended workflow

From the actual project directory, use the installed plugin's bundled scripts:

```bash
bash <plugin-root>/scripts/check-versions.sh
bash <plugin-root>/scripts/vs-record.sh npm lodash 4.17.21 'intentional: compatibility with the current application'
```

An audit compares declared versions with public upstream releases. `DRIFT` reports a newer release without changing dependencies. The recorder makes its own HTTPS upstream request to verify the intended version exists. Older pins need a reason for a successful record. Failed lookups, URL-only legacy records, offline cache, and post-install records must not be presented as successful online checks. Private registries are outside this verifier's scope.

Use `audit-dependencies` or `/check-versions` after a startup warning when useful. Report the command's diagnostic and continue authorized work. Warnings never require exact-version rewrites, splitting shell calls, disabling hooks, waiting for connectivity, or asking permission to continue.

Direct `check-versions.sh`, `vs-record.sh`, and `validate-*.sh` commands can return nonzero to report invalid data, missing manifests, or failed registry requests. CI may use that status. These command results do not create an agent permission gate. Hook adapters convert such findings into warnings and always allow the tool call.

## Evidence and scan scope

Checks live in `.version-sentinel/checks.json`; audit state lives in `.version-sentinel/audit.json`. State includes the canonical project path, timestamps, manifest/lockfile hashes, and session identity when available. Fresh checks can be reused for the same project, package, and version during the configured window (24 hours by default). Changed files or expired evidence can produce another warning. Do not edit state to claim success.

Discovery covers four directory levels and excludes generated/vendor/state directories such as `.git`, `.worktrees`, `node_modules`, `target`, `.venv`, `venv`, `.version-sentinel`, and `__pycache__`. Supported requirements includes can extend beyond discovery depth, within the canonical project root. Deeper unreferenced projects need their own audit for complete reporting. Startup gives optional audit guidance without scanning manifests or contacting registries. A direct audit reports when it finds no supported manifest.

Local paths, URLs, git/workspace sources, NuGet Central Package Management, private registries, some overrides/catalogues, and dynamic shell forms cannot all be verified. Audit reports do not resolve every range, transitive lockfile version, platform marker, or vulnerability. Preserve manifest contents and report parser limitations as tool limitations. Do not remove overrides or change dependencies just to satisfy the parser.

## Missing or invalid manifests

Report the finding and inspect repository evidence. Continue repairs already authorized by the user's task. Version Sentinel does not require a recovery-consent command, and its warnings do not require a new approval request. Ordinary authorization rules still apply to destructive reconstruction or changes outside the task. Never guess dependency contents or claim an invalid manifest passed the audit.

## Platform setup

Claude Code, Codex, Kimi, Gemini, and Copilot adapters use the same advisory policy. Hosts without hooks use the recommended checks manually. `VS_DISABLE=1` suppresses hook warnings; it is not needed to continue work.

Updating source does not reload an installed plugin or change an existing session. Use the normal plugin update path and host trust settings, then start a new session to test advisory behavior. Do not modify installed caches to simulate activation. The hooks are diagnostics, not an operating-system sandbox or a vulnerability scanner.

## npm security diagnostics

Explicit audits use npm audit and OSV by default for public npm lockfile v2/v3 projects. Each provider can be disabled separately with the `security_npm_audit` or `security_osv` plugin setting, or `VS_SECURITY_NPM_AUDIT=0` or `VS_SECURITY_OSV=0`. Findings retain provider attribution, severity, advisory IDs, and links. Missing, stale, or incomplete evidence is reported truthfully.

Public tool hooks only check local cached security evidence. They never contact providers or launch the saved-settings CLI. Candidate versions without a current security check produce a warning. Run `bash <plugin-root>/scripts/security-check.sh audit <project-root>` explicitly to refresh security evidence; this is optional and does not gate authorized work. Low and moderate findings remain visible as advisory text.

The explicit `reconcile-npm-lock.sh` helper can regenerate a lockfile without install scripts and scan it before replacement. Its Git/project/settings evidence and validation errors apply to that explicit command, not permission to continue other work. See [the privacy policy](https://github.com/KSEGIT/Version-Sentinel/blob/main/PRIVACY.md) for upstream package-name disclosures and local evidence storage.

## Optional cleanup of a manifest deleted in Git

An explicit audit can retain a required-path entry after a deliberate committed deletion. The optional `retire-manifest.sh` command removes that stale audit entry and saves a receipt. It is not needed to continue dependency work.

When the user has authorized that metadata cleanup, run from the affected project:

```bash
bash <plugin-root>/scripts/retire-manifest.sh path/to/requirements-old.txt --deleted-by FULL_COMMIT_ID --user-confirmed 'Actual user-approved reason'
```

The flag records an attestation of actual consent; it does not obtain consent. The command verifies an exact regular-file deletion by a single-parent ancestor Git commit, absence from HEAD/index/working tree, and that no live include or lockfile still requires the manifest. It rejects forged ancestry and unproven deletions. It removes only that stale entry, records Git/content/reason details, and invalidates audit evidence. Recreated manifests are discovered normally. A transaction lock preserves receipts and required paths across concurrent audit updates. Explicit audit failures remain truthful diagnostics, and public hooks continue to warn and allow work.
