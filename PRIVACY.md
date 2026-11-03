# Version Sentinel Privacy Policy

Effective date: September 8, 2026

Version Sentinel is an open-source dependency-version guardrail maintained by
Daniel Kiska. This policy explains how the Version Sentinel plugin and its
included scripts handle data.

## Data collection

Version Sentinel does not require an account and does not send data to a server
operated by the maintainer. The maintainer does not collect, store, sell, or
share personal data through Version Sentinel.

## Local data

Version Sentinel records dependency checks in
`.version-sentinel/checks.json` inside the user's project. A record can include
the package ecosystem, package name, intended version, source URL or intentional
pin reason, and timestamp. This file stays in the user's environment unless the
user or another tool chooses to copy, commit, or share it.

Registry lookups can also persist ETags and full registry response bodies in
`.version-sentinel/.etag-cache/` inside the user's project. The cache has no
automatic expiry and stays in the user's environment unless the user or another
tool chooses to copy, commit, or share it.

## Network requests

To check package versions, Version Sentinel can send package names and standard
HTTP request metadata to public package registries, such as npm, PyPI,
crates.io, and NuGet. Those services process requests under their own privacy
policies. The coding-agent host can also process prompts, files, and tool output
under the host provider's terms and privacy policy.

## Data retention and deletion

Version Sentinel has no maintainer-operated data store. Users control local
records and can delete `.version-sentinel/checks.json` at any time. To remove
all Version Sentinel local data, delete `.version-sentinel/checks.json` and
`.version-sentinel/.etag-cache/`.

## Security

Version Sentinel is designed to read public registry metadata and write local
check records. No software can be guaranteed secure. Users should review the
source code and use the plugin only in environments they trust.

## Children

Version Sentinel is a developer tool and is not directed to children under 13.

## Changes

Material changes to this policy will be published in this repository with a new
effective date.

## Contact

For privacy questions, open an issue at
<https://github.com/KSEGIT/Version-Sentinel/issues>.

Startup audit state stores the canonical project path, manifest and lockfile names and hashes, audit time, and session ID when supplied. Recovery state stores the approved path, missing/invalid condition, caller-provided consent reason, and expiry time. Online check records store upstream URL, intended/latest versions, verification time, and project path. These stay in the local .version-sentinel directory. Registry requests send package names to the canonical public registries; do not put sensitive information in consent reasons.

If the project directory is not writable, package check records use `${CLAUDE_PLUGIN_DATA:-$HOME/.claude/plugins/data/version-sentinel}/checks.json`. Audit and recovery evidence still require writable project state; that fallback cannot satisfy a missing project audit. To remove fallback records, delete that checks.json in the plugin data directory (or the directory when no longer needed).
