# Dependency enforcement

Version Sentinel runs an online audit at session start. Dependency edits and recognized install, restore, lockfile install, and build commands need a successful audit for their actual project directory. Reading files, asking the user, recording version checks, and retrying an audit remain available when dependency work is blocked.

From the project directory, use the plugin's bundled scripts:

```bash
bash <plugin-root>/scripts/check-versions.sh
bash <plugin-root>/scripts/vs-record.sh npm lodash 4.17.21 https://www.npmjs.com/package/lodash
```

The recorder makes its own HTTPS upstream request. It checks that the intended version exists and compares it with the latest release. A URL supplied by an agent is not evidence. For an older version, provide an explicit reason:

```bash
bash <plugin-root>/scripts/vs-record.sh npm lodash 4.17.21 'intentional: compatibility with the current application'
```

Older pins still need a successful online check. Network errors, stale offline cache, legacy URL-only records, and post-install records cannot authorize dependency changes. The post-install compatibility hook does not create checks. Existing legacy records need to be recorded again. Private registries are not supported by the current canonical upstream verifier; an intentional reason does not bypass that restriction.

## Audit evidence

The audit reports newer releases as `DRIFT`, without changing dependency versions. Version drift does not fail the audit. Failed lookups, invalid manifests, or missing required manifests do fail it.

Audit state in `.version-sentinel/audit.json` names the canonical project directory, required manifests, and hashes of manifests and known lockfiles. Changes, additions, deletions, failed audit retries, expiry, and a different session (where the host supplies a session ID) invalidate the evidence. Online package checks are separate from audit evidence and are stored in `.version-sentinel/checks.json`; they are bound to the project and expire after 24 hours by default. A successful audit does not authorize an unrecorded package addition.

Discovery covers four directory levels. It excludes generated/vendor/state directories: `.git`, `.worktrees`, `node_modules`, `target`, `.venv`, `venv`, `.version-sentinel`, and `__pycache__`. Git-tracked manifests, previous required manifests, and supported requirements includes are checked for deletion. Lockfiles can identify a missing source manifest. Explicit requirements and constraints includes can extend beyond the discovery depth, including transitively, but must resolve inside the canonical project root, stay outside excluded directories, and use `requirements*.txt` or `constraints*.txt` names. These included files are fingerprinted and audited; changes or deletion invalidate the evidence. Deeper files without an explicit include are not discovered or authorized. Explicit command input files must belong to the successful audit. Unreferenced deeper projects need their own audit from their project directory.

A project with no supported manifest cannot complete an audit. In a repository with deliberately invalid test fixtures, the root audit may fail. Audit the actual application directory rather than treating those failures as success.

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

This is an agent hook guardrail, not an operating-system sandbox. It cannot intercept arbitrary shell/Python writes, generated commands, every package-manager alias or script, or manual edits outside hooked tools. Local evidence and consent files are not tamper-proof against a process with write access. Local/git/workspace sources and NuGet Central Package Management remain outside direct registry-version verification. Audit reports compare declared versions/bounds; they do not resolve every range, transitive lockfile version, workspace catalogue, platform marker, or vulnerability.

Claude Code, Codex, Kimi, Gemini, and Copilot startup definitions invoke `session-start.sh`; dependency hooks enforce completion even if startup exits or times out. A host without hooks requires the same steps manually. Host-specific tool dispatch still needs verification on that host. Updating source does not reload an already trusted installed plugin. Review the PR, update the installed plugin through its normal installation path, approve the changed hooks when prompted, and start a new session. Do not modify installed cache files to simulate activation.

## Routine and live checks

`bash tests/run.sh` uses offline registry fixtures. Live registry checks and actual host hook dispatch are separate checks; offline tests alone do not prove installed-plugin activation. Run `bash scripts/check-versions.sh` on relevant application manifests before release.

Nonempty npm/Yarn/pnpm override, resolution, catalogue, and package-extension tables, plus Cargo patch/replace tables, currently block as unsupported dependency selectors. They cannot be treated as metadata. Direct resolver forms such as `cargo install`, package-manager `exec`, and `uv run --with` are rejected rather than authorized from an unrelated audit. Use supported manifest edits with exact online evidence; these commands do not gain support merely by splitting the shell call.

On Windows, Git Bash's `cygpath` must be available to translate MSYS paths carried inside JSON. Native drive and UNC paths remain native; mapper failure blocks rather than guessing a location.
