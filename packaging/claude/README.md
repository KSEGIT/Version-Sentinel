# Version Sentinel for Claude Code

Version Sentinel blocks dependency additions and version changes until Claude
verifies the intended version against its public package registry and records
the check. It supports npm, Python, Cargo, and NuGet manifests.

## Requirements

Install Bash, jq, curl, and Python 3.11 or later on your PATH. On Windows, use
Git Bash and install Python separately. Registry checks require internet access.

## Use

The startup hook audits the current project. Before changing a dependency,
verify its version and use `/version-sentinel:vs-record` to save the check.
Use `/version-sentinel:check-versions` to run another audit. The included
version-sentinel skill explains the required workflow and recovery steps.

Hooks enforce the recorded checks before supported edits and install commands.
Read [the enforcement guide](docs/enforcement.md) for supported operations and
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
