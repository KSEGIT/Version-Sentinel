---
name: version-sentinel
description: Use when adding, bumping, or changing a dependency in package.json, requirements*.txt, constraints*.txt, pyproject.toml, Cargo.toml, *.csproj, *.fsproj, or *.vbproj. Triggered automatically by version-sentinel's PreToolUse hook (where the host supports hooks) — this skill explains how to satisfy the block and record a version check.
---

# Version Sentinel — Workflow

The `version-sentinel` setup blocks dependency changes until you've verified the package version against its upstream registry. Here's the required flow. (On hosts without hook support, such as Zed, this same flow applies manually — follow it whenever you touch a manifest or run an install command.)

## Mandatory startup audit

From the project directory, run the bundled `scripts/check-versions.sh` at startup and after manifests or lockfiles change. Hooks require successful current project evidence before dependency work. Registry lookup failure blocks; newer-release drift is reported without upgrading dependencies. File inspection, user questions, audit retries, and version recording remain available.

If a required manifest is missing or invalid, ask Daniel before recreating or repairing that exact file. Do not guess dependencies. Only after actual consent, run `bash scripts/recover-manifest.sh approve FILE --user-confirmed 'REASON'`. This records an attestation; it does not obtain approval or create contents. Online-verify proposed dependencies before writing approved contents, then rerun the audit. Do not use the consent flag without approval.

## When you see a BLOCKED message

If a tool call exits 2 with `BLOCKED: version-sentinel`, you must:

1. **Look up the latest version.** Use a web search first:
   - `npm`:      search `"<pkg> latest version site:npmjs.com"`
   - `pip`/`pyproject`: search `"<pkg> latest version site:pypi.org"`
   - `csproj`:   search `"<pkg> latest version site:nuget.org"`
   - `cargo`:    search `"<pkg> latest version site:crates.io"`

   If web search is unavailable, fetch the registry URL directly, or consult a docs tool (e.g. context7) for the package.

2. **Record the check.** Run in the terminal:

       bash scripts/vs-record.sh <ecosystem> <pkg> <version-you-intend-to-install> <source-url>

   The source must be the canonical `https://` package page or upstream URL, or `intentional:` followed by a nonempty reason for a deliberate pin. The recorder makes its own successful online upstream request and verifies that the exact intended version exists. Older pins need both online evidence and a reason.

3. **Retry with the verified version.** If the blocked input omitted the version or used a floating tag such as `latest`, rewrite it first. For example, use `npm install lodash@4.17.21`, not `npm install lodash` or `npm install lodash@latest`.

Local paths, URLs, git sources, and workspace dependencies are outside registry-version checks. A NuGet `PackageReference` without `Version` may use Central Package Management, so the manifest gate ignores that form.

## Intentional non-latest pins

If you genuinely intend to install an older version (CVE mitigation or compatibility), record with:

    bash scripts/vs-record.sh <ecosystem> <pkg> <version> "intentional: <brief reason>"

After a successful online check and current audit, this can pass the hook and is flagged as `intentional-pin` (not `DRIFT`) in `bash scripts/check-versions.sh` output.

## What NOT to do

- Don't fake a source URL you didn't actually see. The recorder validates canonical upstream data; a URL string alone is not evidence.
- Don't try to bypass the hook with `git commit --no-verify` or similar — the hook runs on file edits and terminal commands, not on git.
- Don't `unset VS_DISABLE` without the user's awareness; that's an escape hatch for throwaway sessions, not normal flow.

## Audit command

`bash scripts/check-versions.sh` scans manifests within 4 directory levels of the current directory and reports drift. Run it before tagging a release.

Legacy URL-only records, automatic post-install records, and stale offline responses cannot authorize dependency changes. Private registries are not supported by the current canonical verifier; a reason cannot bypass online verification. Hooks do not intercept arbitrary shell/Python file writes. See docs/enforcement.md for scan scope, recovery trust, and host activation limits.
