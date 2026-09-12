---
name: version-sentinel
description: Use when adding, bumping, or changing a dependency in package.json, requirements*.txt, constraints*.txt, pyproject.toml, Cargo.toml, *.csproj, *.fsproj, or *.vbproj. Triggered automatically by version-sentinel's PreToolUse hook (where the host supports hooks) — this skill explains how to satisfy the block and record a version check.
---

# Version Sentinel — Workflow

The `version-sentinel` setup blocks dependency changes until you've verified the package version against its upstream registry. Here's the required flow. On hosts without hook support, follow the same flow whenever you change a manifest or run an install command.

## When you see a BLOCKED message

If a tool call exits 2 with `BLOCKED: version-sentinel`, you must:

1. **Resolve the intended dependency.** Identify the ecosystem and package. For
   a public package without a version, treat it as a latest-version request and
   look up the current release. Ask the user only when the dependency is
   ambiguous or private. For a private registry, ask for its URL instead of
   guessing a public source.

2. **Verify the version.** For a latest-version request, look up the current
   release. For a deliberate pin, verify that the requested version exists and
   record the reason as described below. Use a web search first:
   - `npm`:      search `"<pkg> latest version site:npmjs.com"`
   - `pip`/`pyproject`: search `"<pkg> latest version site:pypi.org"`
   - `csproj`:   search `"<pkg> latest version site:nuget.org"`
   - `cargo`:    search `"<pkg> latest version site:crates.io"`

   If web search is unavailable, fetch the registry URL directly, or consult a current documentation tool for the package.

3. **Record the check.** From the user's project directory, locate this plugin's bundled `scripts/vs-record.sh` and run:

       bash <plugin-root>/scripts/vs-record.sh <ecosystem> <pkg> <version-you-intend-to-install> <source-url>

   The source must be an `http(s)://` URL from your search OR prefixed with `intentional:` for deliberate pins.

4. **Retry with the verified version.** If the blocked input omitted the version or used a floating tag such as `latest`, rewrite it first. For example, use `npm install lodash@4.17.21`, not `npm install lodash` or `npm install lodash@latest`.

Local paths, URLs, git sources, and workspace dependencies are outside registry-version checks. A NuGet `PackageReference` without `Version` may use Central Package Management, so the manifest gate ignores that form.

## Intentional non-latest pins

If you genuinely intend to install an older version (CVE mitigation, compat, private registry), record with:

    bash <plugin-root>/scripts/vs-record.sh <ecosystem> <pkg> <version> "intentional: <brief reason>"

This passes the hook and is flagged as `intentional-pin` (not `DRIFT`) in the audit output.

## What NOT to do

- Don't fake a source URL you didn't actually see. The skill contract assumes honest reporting.
- Don't try to bypass the hook with `git commit --no-verify` or similar. The hook runs on file edits and terminal commands, not on git.
- Don't `unset VS_DISABLE` without the user's awareness; that's an escape hatch for throwaway sessions, not normal flow.

## Audit command

From the user's project directory, run `bash <plugin-root>/scripts/check-versions.sh`. It scans manifests within four directory levels and reports drift. Run it before tagging a release.
