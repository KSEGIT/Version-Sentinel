# Version Sentinel Privacy Policy

Effective date: November 15, 2026

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

Version lookups use public endpoints without package-registry authentication.
Those curl requests ignore default curl configuration files. The separate npm
security check runs `npm audit`, which sends the dependency tree to npm's
configured registry and can use registry credentials from npm configuration.
OSV checks send npm package names and exact versions to the public OSV API;
this can disclose private package names present in a proposed change or lockfile.
OSV does not require an API key. Both security providers are enabled by default
and can be disabled independently; see the security settings in
docs/enforcement.md.

## Data retention and deletion

Version Sentinel has no maintainer-operated data store. Users control local
records and can delete `.version-sentinel/checks.json` at any time. To remove
all project-local Version Sentinel data, delete the `.version-sentinel/`
directory, including check records, caches, audit and security evidence.

## Security

Version Sentinel reads registry and advisory metadata and writes local check
records. Security evidence also stores project paths, manifest/lockfile hashes,
provider settings, scan time and advisory findings. No software can be guaranteed secure. Users should review the
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
