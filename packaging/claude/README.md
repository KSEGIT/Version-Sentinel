# Version Sentinel for Claude Code

Version Sentinel warns about missing or stale dependency checks and recommends
verifying the intended version against its public package registry. Hooks never
block tools. It supports npm, Python, Cargo, and NuGet manifests.

## Requirements

Install Bash, jq, curl, and Python 3.11 or later on your PATH. On Windows, use
Git Bash and install Python separately. Registry checks require internet access.

## Commands

The startup hook suggests an optional audit and makes no registry requests. For dependency work,
consider verifying its version and using `/version-sentinel:vs-record` to save the check.
Use `/version-sentinel:vs-refresh` to run an audit and show when the project audit evidence
expires. `/version-sentinel:check-versions` remains available for the standard audit report.

Hooks return status 0 for every result. Audit failures, parser limits, and missing
manifests do not require a pause or a recovery-consent command.
Read [the advisory guide](https://github.com/KSEGIT/Version-Sentinel/blob/main/docs/enforcement.md) for supported operations and
limits. The package includes readable scripts for each hook and command.

## Privacy

The plugin queries public package metadata and saves evidence in the project's
`.version-sentinel` directory. It needs no account or registry credentials and
does not send data to a maintainer-operated server. See the
[privacy policy](PRIVACY.md) for local storage and network details.

## Source and license

Daniel Kiska maintains Version Sentinel at
[KSEGIT/Version-Sentinel](https://github.com/KSEGIT/Version-Sentinel).
This Claude package contains the runtime source, commands, skill, and reviewer
agent. Website files, development tools, and tests remain in the source
repository. Version Sentinel is available under the [MIT license](LICENSE).
