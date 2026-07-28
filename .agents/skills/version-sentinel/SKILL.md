---
name: version-sentinel
description: Use when adding, bumping, or changing a dependency in package.json, requirements*.txt, constraints*.txt, pyproject.toml, Cargo.toml, *.csproj, *.fsproj, or *.vbproj. Triggered automatically by version-sentinel's PreToolUse hook (where the host supports hooks) — this skill explains how to satisfy the block and record a version check.
---

# Version Sentinel — Workflow

The `version-sentinel` setup blocks dependency changes until you've verified the package version against its upstream registry. Here's the required flow. (On hosts without hook support, such as Zed, this same flow applies manually — follow it whenever you touch a manifest or run an install command.)

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

   The source must be an `http(s)://` URL from your search OR prefixed with `intentional:` for deliberate pins.

3. **Retry the original edit or install.** The hook will see the fresh entry and let the tool call through.

## Intentional non-latest pins

If you genuinely intend to install an older version (CVE mitigation, compat, private registry), record with:

    bash scripts/vs-record.sh <ecosystem> <pkg> <version> "intentional: <brief reason>"

This passes the hook and is flagged as `intentional-pin` (not `DRIFT`) in `bash scripts/check-versions.sh` output.

## What NOT to do

- Don't fake a source URL you didn't actually see. The skill contract assumes honest reporting.
- Don't try to bypass the hook with `git commit --no-verify` or similar — the hook runs on file edits and terminal commands, not on git.
- Don't `unset VS_DISABLE` without the user's awareness; that's an escape hatch for throwaway sessions, not normal flow.

## Audit command

`bash scripts/check-versions.sh` scans manifests within 4 directory levels of the current directory and reports drift. Run it before tagging a release.
