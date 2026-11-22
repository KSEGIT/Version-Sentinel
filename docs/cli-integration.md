# Real CLI integration tests

The `CLI integration` workflow runs the real Codex and Claude Code CLIs against
scripted APIs on localhost. It runs on pull requests and can be started manually.
It needs no API secrets and makes no paid model calls. GitHub Actions runner
usage still follows the repository's billing plan.

Each adapter uses a clean configuration directory and a scratch `package.json`.
The local API returns a fixed dependency edit tool call. The CLI loads Version
Sentinel, executes the tool, and runs its real hooks. The test checks the file
change and the advisory warning. A separate run without the plugin must execute
the edit without the Version Sentinel warning.

Both adapters run a fixture audit in all cases, and the real recorder in the
recorded case. They check the exact tool payload with the strict validator to
prove the missing-record reason, then check the real hook warning and file edit.
The recorded case must edit without a dependency warning. Evidence must show both
the pre-edit and post-edit hooks. Registry fixtures keep these checks offline.

Codex `exec --json` omits hook lifecycle events. Its adapter uses a test-only Bash
tracing shim to capture the real hook process input, output, and exit status. The
shim forwards these unchanged and executes the installed scripts with real Bash;
it does not replace the plugin manifest or hook logic. This proves that the hook
emits a warning and allows the edit, not that headless Codex displays the warning.

Run locally with Python 3, Bash, jq, and the relevant CLI on PATH:

```bash
python3 tests/integration/codex_cli.py --output-dir /tmp/vs-codex-evidence
python3 tests/integration/claude_cli.py --output-dir /tmp/vs-claude-evidence
```

Use a new output directory for each run. Tests fail if a required CLI is missing;
they do not silently skip. The CI workflow pins the CLI versions used for local
verification. Change those pins deliberately and run both adapters after upgrades.

CLI output and local API requests are retained as CI artifacts for 14 days,
including on failure. The adapters set dummy credentials and isolate CLI config;
never supply real API keys to these tests.

## Scope

These tests cover actual plugin loading, tool execution, and advisory hook
behavior through the CLI. The existing `bash tests/run.sh` suite covers the
wider set of parsers, registries, security providers, and hook payloads.

The mock selects tool calls; it does not exercise model reasoning, hosted API
authentication, real registry availability, or all marketplace installation and
update paths. A paid model smoke test remains an optional separate check.
