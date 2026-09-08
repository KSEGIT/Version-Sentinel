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

## Network requests

To check package versions, Version Sentinel can send package names and standard
HTTP request metadata to public package registries, such as npm, PyPI,
crates.io, and NuGet. Those services process requests under their own privacy
policies. The coding-agent host can also process prompts, files, and tool output
under the host provider's terms and privacy policy.

## Data retention and deletion

Version Sentinel has no maintainer-operated data store. Users control local
records and can delete `.version-sentinel/checks.json` at any time.

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
