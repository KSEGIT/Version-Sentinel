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
