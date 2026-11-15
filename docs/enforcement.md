# Dependency enforcement

Version Sentinel runs an online audit at session start. Dependency edits and recognized install, restore, lockfile install, and build commands need a successful audit for their actual project directory. Reading files, asking the user, recording version checks, and retrying an audit remain available when dependency work is blocked.

From the project directory, use the plugin's bundled scripts:

```bash
bash <plugin-root>/scripts/check-versions.sh
bash <plugin-root>/scripts/vs-record.sh npm lodash 4.17.21 https://www.npmjs.com/package/lodash
```

After a startup audit warning, use the `audit-dependencies` skill or the existing `/check-versions` command. The skill resolves the script from its own plugin installation and runs it from the affected project, so an older script in the project cannot replace it. The visible warning includes a shell-quoted `cd PROJECT && bash INSTALLED_SCRIPT` retry command. Run that command to see the full diagnostic, resolve the reported cause, and retry; dependency work stays blocked until an audit succeeds.

The recorder makes its own HTTPS upstream request. It checks that the intended version exists and compares it with the latest release. A URL supplied by an agent is not evidence. For an older version, provide an explicit reason:

```bash
bash <plugin-root>/scripts/vs-record.sh npm lodash 4.17.21 'intentional: compatibility with the current application'
```

Older pins still need a successful online check. Network errors, stale offline cache, legacy URL-only records, and post-install records cannot authorize dependency changes. The post-install compatibility hook does not create checks. Existing legacy records need to be recorded again. Private registries are not supported by the current canonical upstream verifier; an intentional reason does not bypass that restriction.

## Audit evidence

The audit reports newer releases as `DRIFT`, without changing dependency versions. Version drift does not fail the audit. Failed lookups, invalid manifests, or missing required manifests do fail it.

Audit state in `.version-sentinel/audit.json` names the canonical project directory, required manifests, and hashes of manifests and known lockfiles. Changes, additions, deletions, failed audit retries, expiry, and a different session (where the host supplies a session ID) invalidate the evidence. Online package checks are separate from audit evidence and are stored in `.version-sentinel/checks.json`; they are bound to the project and expire after 24 hours by default. A successful audit does not authorize an unrecorded package addition.

A manual `check-versions.sh` run uses an explicit nonempty `VS_SESSION_ID` first, then Codex's `CODEX_THREAD_ID` environment variable. This binds a successful audit in an explicit command working directory to the session whose tool hook will check it. If neither identity is supplied, a retry retains the previously recorded startup session. Run the audit from the actual project directory; do not edit audit JSON or remove npm overrides to make a gate pass.

Discovery covers four directory levels. It excludes generated/vendor/state directories: `.git`, `.worktrees`, `node_modules`, `target`, `.venv`, `venv`, `.version-sentinel`, and `__pycache__`. Git-tracked manifests, previous required manifests, and supported requirements includes are checked for deletion. Lockfiles can identify a missing source manifest. Explicit requirements and constraints includes can extend beyond the discovery depth, including transitively, but must resolve inside the canonical project root, stay outside excluded directories, and use `requirements*.txt` or `constraints*.txt` names. These included files are fingerprinted and audited; changes or deletion invalidate the evidence. Deeper files without an explicit include are not discovered or authorized. Explicit command input files must belong to the successful audit. Unreferenced deeper projects need their own audit from their project directory.

At startup, a folder with no supported or required manifest and no recognized dependency files is skipped silently, without registry requests or completed audit evidence. This applies to the default, Gemini, and Copilot modes. Previous required manifests, Git-tracked deleted manifests, and recognized lockfiles or dependency configuration such as `Directory.Packages.props` still require an audit and report missing manifests. A direct audit or dependency gate still rejects a project with no supported manifest. In a repository with deliberately invalid test fixtures, the root audit may fail. Audit the actual application directory rather than treating those failures as success.

Startup selects the project from the hook payload `cwd` before reading or changing audit state; the launch directory is only the fallback when no valid project directory is supplied. Target evidence is revoked before checking `jq` and `curl`, so missing prerequisites cannot leave an older audit authorized. A reported audit failure at session start returns advisory hook status 0. Startup displays a warning and supplies the full audit diagnostic and retry command as session context. Dependency work remains blocked because the failed audit revokes earlier evidence. This status allows file inspection and questions; it does not mean the audit passed. A direct `check-versions.sh` failure and dependency gates still return status 2. Invalid startup payloads, missing prerequisites, and unexpected audit crashes remain hook failures. Gemini startup returns JSON context for both successful and blocked audits.

The shared Copilot and VS Code Local repository hook passes `--copilot` to `session-start.sh`. This mode returns JSON with identical context in top-level `additionalContext` for [Copilot](https://docs.github.com/en/copilot/reference/hooks-reference#sessionstart--sessionstart) and `hookSpecificOutput.additionalContext` with `hookEventName: "SessionStart"` for [VS Code Local](https://code.visualstudio.com/docs/agents/reference/hooks-reference#sessionstart). Both successful and blocked audits use this format. Blocked context includes the full audit diagnostic, warning, and retry command. The default Claude/Codex output and Gemini JSON format are unchanged.

## Missing or invalid manifests

Stop dependency work and ask Daniel whether to create or repair the specific manifest. Inspect the repository and agree on contents first. Do not guess dependencies or recreate a deleted file silently. After the user confirms, record that consent from the project directory:

```bash
bash <plugin-root>/scripts/recover-manifest.sh approve package.json --user-confirmed 'Daniel approved recreating this file from the reviewed contents'
```

This command records the caller's explicit attestation of user consent. It does not contact the user, create files, or prove that a conversation occurred. Agents must call it only after actual approval. Consent is limited to that project, path, current missing/invalid state, and 24 hours. Valid files cannot be replaced through recovery approval. Deletion and moving a required manifest away remain blocked.

Verify and record each proposed registry dependency before writing the approved recovery contents. Recovery permits that specific write while the audit is blocked. Then rerun the audit before other dependency work. Replacing an invalid file still requires the agreed contents; approval is not permission for destructive reconstruction.

## Hook coverage and limits

Structured edits and supported Codex `apply_patch` inputs are reconstructed and validated before execution, including multiple files. Unsupported or ambiguous relevant input blocks. Safe metadata edits can proceed without dependency authorization. Missing prerequisites block inspected writes and commands instead of silently allowing them.

Shell handling recognizes literal package-manager commands, common wrappers, literal directory changes, directory flags, and explicit manifest inputs. Bare installs, lockfile installs, restore commands, and recognized build commands require audit evidence. Named registry additions also require a fresh online check for their exact version. Floating update commands must be replaced with explicit verified changes. Dynamic directories and unsupported command forms can require separate literal tool calls.

This is an agent hook guardrail, not an operating-system sandbox. It cannot intercept arbitrary shell/Python writes, generated commands, every package-manager alias or script, or manual edits outside hooked tools. Local evidence and consent files are not tamper-proof against a process with write access. Local/git/workspace sources and NuGet Central Package Management remain outside direct registry-version verification. Version reports compare declared versions/bounds. npm security checks separately inspect supported package-lock resolved versions, including transitive dependencies. Unsupported lockfiles, local/git/workspace sources and incomplete enabled provider checks cannot produce a clean npm security result. Other ecosystems have no advisory coverage in this release.

Claude Code, Codex, Kimi, Gemini, and Copilot startup definitions invoke `session-start.sh`; dependency hooks enforce completion even if startup exits or times out. A host without hooks requires the same steps manually. Host-specific tool dispatch still needs verification on that host. Updating source does not reload an already trusted installed plugin or change an existing session's startup warning. Review the PR, update the installed plugin through its normal installation path, approve the changed hooks when prompted, and start a new session. Do not modify installed cache files to simulate activation.

## Routine and live checks

`bash tests/run.sh` uses offline registry fixtures. Live registry checks and actual host hook dispatch are separate checks; offline tests alone do not prove installed-plugin activation. Run `bash scripts/check-versions.sh` on relevant application manifests before release.

Nested or version-qualified npm overrides, Yarn/pnpm resolution, catalogue and package-extension tables, plus Cargo patch/replace tables, currently block as unsupported dependency selectors. Flat npm package-name overrides with string selectors are tracked. They cannot be treated as metadata. Direct resolver forms such as `cargo install`, package-manager `exec`, and `uv run --with` are rejected rather than authorized from an unrelated audit. Use supported manifest edits with exact online evidence; these commands do not gain support merely by splitting the shell call.

On Windows, Git Bash's `cygpath` must be available to translate MSYS paths carried inside JSON. Native drive and UNC paths remain native; mapper failure blocks rather than guessing a location.


## npm security checks

npm advisory checks (`npm audit`) and OSV checks are both enabled by default. Each
has an independent boolean in plugin settings: `security_npm_audit` and
`security_osv`. Hosts without that settings UI can set `VS_SECURITY_NPM_AUDIT`
and `VS_SECURITY_OSV`. The corresponding plugin option environment names are
`CLAUDE_PLUGIN_OPTION_SECURITY_NPM_AUDIT` and
`CLAUDE_PLUGIN_OPTION_SECURITY_OSV`; explicit `VS_*` values take priority.
Invalid values block rather than silently disabling a provider. For example,
`VS_SECURITY_OSV=0` disables only OSV; npm audit remains enabled. Disabled coverage
is reported explicitly and must not be described as a clean advisory scan.

Claude exports plugin option variables to hook processes, not commands run
through its Bash tool or an independent terminal. When an option is absent from
both environments above, the security wrapper queries Claude's installed-plugin
inventory and reads saved non-sensitive options for the exact installation
through `claude plugin configure FULL_ID --json` (Claude Code 2.1.285 or later).
It does not read host settings or credential files directly. An ambiguous,
unsupported or failed lookup blocks as unknown before any advisory request.
Explicit shell values and hook option values still take priority. This also
applies to the lock reconciliation command.
When already reading saved provider options, the resolver also uses saved
`window_hours` if neither window environment variable is present. It validates
the same 1–168 hour range as the engine and starts no CLI lookup for the window
alone. Standalone scripts with explicit provider values can set
`VS_WINDOW_HOURS` explicitly to keep the same freshness policy.

With no Claude CLI or no matching installed plugin, a checkout or standalone CI
script uses explicit `VS_SECURITY_*` values, otherwise both providers default
to enabled. A standalone checkout does not inherit options from a different
installed copy. Set the environment explicitly when invoking that checkout or
when using a host that does not export these options. The source and scope are
documented in Claude's [manifest reference](https://code.claude.com/docs/en/plugins/manifest-reference#reference-a-saved-value)
and [configuration CLI reference](https://code.claude.com/docs/en/plugins/cli-reference#plugin-configure).
Projects without npm manifests or lockfiles skip this Claude settings lookup;
the existing evidence gate still checks for removed project files.

The startup audit and explicit `bash scripts/check-versions.sh` run both enabled
providers before creating successful audit evidence. Supported structured npm
manifest/lockfile changes and recognized npm commands trigger a post-tool scan
when security evidence is missing, stale or changed. A post-tool failure cannot
undo the tool's completed write; it reports the problem and leaves further
dependency work blocked. Current evidence avoids repeated network scans for
unchanged state. Unrelated reads and edits do not trigger advisory requests.

Before supported named dependency additions or version changes, OSV checks the
proposed exact npm package version. npm audit checks the currently resolved tree;
it does not predict a future resolver result. The tree is checked again after a
change. An intentional-version-pin reason never waives an advisory or an enabled
provider failure. Direct lockfile writes also require successful current startup
and security evidence before the proposed lock versions are checked. A missing
or unsupported current npm lock is incomplete and cannot gain a clean result
through a lockfile write. For an explicit migration or initial lock bootstrap,
configure provider settings deliberately, complete the current audit, write the
reviewed lock, then enable both providers and rerun the audit. The hook never
automatically exempts lockfile repair from the current audit. No hook runs
`npm audit fix`, changes a package version, or installs a package to repair a
finding.

Supported resolved-tree input is `package-lock.json` version 2 or 3, discovered
within the same four-level project scope. Both direct and transitive resolved
packages are checked. Initial source coverage is canonical HTTPS npm tarballs
from `registry.npmjs.org` whose package name and version match the lock entry.
Aliases, private/mirror registries, arbitrary tarballs, local/git/workspace
sources and mismatched package metadata are incomplete. Missing nodes in the
resolved dependency graph, including optional or peer edges, are incomplete
rather than silently omitted. Missing or unsupported locks, unresolved entries and
unsupported source coverage report unknown/incomplete; they cannot authorize a
clean security result while a provider is enabled. Other lockfile formats and
other ecosystems do not gain security coverage from this change.

High and critical findings block by default. Missing severity is explicit and
blocks conservatively. Reports retain provider attribution, advisory IDs and
links, severity, affected ranges and fixed versions where supplied. Findings
with common advisory aliases are combined without dropping their provider
records. A failed request, malformed or partial response, unavailable tool or
unsupported enabled check is unknown/incomplete, never clean.

Security evidence is local project state under `.version-sentinel/`. It binds
the canonical project directory, manifest/lockfile contents, provider settings
and scan time. Changes, settings changes, expired or future timestamps, and
failed rescans invalidate it. The default freshness window is 24 hours through
`window_hours` / `VS_WINDOW_HOURS`. An audit verifies the same snapshot before and
after network requests, so a file change during a scan cannot authorize it.

For a focused release or CI security gate, run from the actual application root:

```bash
bash /path/to/version-sentinel/scripts/security-check.sh audit "$PWD"
```

Exit 0 permits the configured policy; exit 2 blocks. Run
`bash /path/to/version-sentinel/scripts/check-versions.sh` for both version and
security checks. A result with disabled providers has reduced coverage. A clean
advisory scan means no known matching findings in the enabled providers at scan
time. It is not proof of safety or exploitability.

npm audit submits the dependency tree to npm's configured registry and can use
that registry's configured credentials. OSV receives package names and exact
versions, including private names if those appear in the supported tree or a
proposed package. OSV's public API needs no API key. Those services apply their
own privacy policies; see [PRIVACY.md](../PRIVACY.md). Official interfaces:
[npm audit](https://docs.npmjs.com/cli/v11/commands/npm-audit/),
[OSV batch API](https://google.github.io/osv.dev/post-v1-querybatch/).

### Reconcile a lock after an approved npm manifest change

A structured dependency edit is checked against the current audit before the
manifest changes. When that edit changes an existing npm project, Version
Sentinel can record one exact pending transition in
`.version-sentinel/reconcile.json`. This record is not a clean audit and does
not permit a general install. It binds the canonical project, the exact approved
manifest bytes, the unchanged prior lock and other audited dependency files,
provider settings, session when supplied, and freshness window.

After writing the approved manifest, explicitly run the installed helper:

```bash
bash /path/to/version-sentinel/scripts/reconcile-npm-lock.sh "$PWD" package.json
```

Edit and reconcile one npm project at a time. Multi-project dependency edits
must use separate tool calls with a completed reconciliation between them.
For a nested project, give its `package.json` path relative to the audited root.
The helper resolves only a temporary copy with fixed `npm install
--package-lock-only --ignore-scripts` options. It does not run package scripts,
install `node_modules`, accept caller-supplied npm flags, run `npm audit fix`, or
start automatically after an edit. OSV checks the generated lock before the
helper replaces the real lock. Both enabled providers then scan the new tree
through the full version audit before successful evidence is restored. A
provider failure leaves dependency work blocked, with findings visible.

A supported structured write of the exact matching lock post-image can also
use this transition. Its root declarations must match the approved manifest,
and its proposed exact versions still pass the enabled OSV check. Run
`check-versions.sh` afterward to restore the full version audit. Unrelated file,
manifest, lock, settings, session or time changes invalidate the transition.
Missing initial locks still require the documented bootstrap policy; this path
only reconciles an existing lock after a freshly audited, approved edit.
