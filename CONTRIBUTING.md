# Contributing to version-sentinel

Thanks for helping make dependency drift harder to ignore. This guide covers local setup, tests, and how to add a new ecosystem.

## Local setup

Prereqs:

- `bash` (on Windows, use **Git Bash** — the tests and scripts assume POSIX `bash`, not `cmd` or PowerShell)
- `jq` (1.6+)
- `curl`
- `python3` 3.11+

Clone the repo and verify each tool is on your `PATH`:

```bash
bash --version && jq --version && curl --version && python3 --version
```

No build step — the plugin is shell scripts + markdown.

## Running tests

```bash
bash tests/run.sh
```

`tests/run.sh` discovers every `tests/test_*.sh` unit test plus `tests/integration/smoke.sh` (end-to-end block → record → retry → allow). **All tests must pass before you open a PR.** Unit tests are offline and use fixtures under `tests/fixtures/`; they must never hit the real network.

## Adding a new ecosystem

To teach version-sentinel a new manifest type (e.g. `go.mod`, `Gemfile`), touch these files in order:

1. **`scripts/lib/parse-manifest.sh`** — add a `parse_<eco>` function that reads the manifest and emits `pkg\tversion` lines (tab-separated, one per line).
2. **`scripts/lib/parse-install-cmd.sh`** — add a regex for the ecosystem's install command (e.g. `go get`, `bundle add`) so the hook can detect additions from bash commands too.
3. **`scripts/lib/registries.sh`** — add `registry_latest_<eco>` that returns the latest version string from the upstream registry's HTTP API. Use `curl -fsSL` + `jq`. Register it in the `registry_latest` dispatcher.
4. **`scripts/lib/sidecar.sh`** — the ecosystem name is just a string; no change needed unless you want explicit validation.
5. **`scripts/vs-record.sh`** — add the new ecosystem to the accepted-names whitelist.
6. **`tests/fixtures/`** — add a representative manifest fixture plus an offline registry response JSON.
7. **`tests/test_parse_<eco>.sh`** — new unit test for the parser. Extend `tests/test_registries_offline.sh` to cover the new registry helper against the fixture JSON (never live network).
8. **`README.md`** — add the new ecosystem to the supported-ecosystems table.

Run `bash tests/run.sh` — all green before you open the PR.

## Commit style

**Conventional Commits are required.** release-please parses commit messages to compute the next version and generate `CHANGELOG.md`.

| Prefix                            | Bump  |
| --------------------------------- | ----- |
| `feat:`                           | minor |
| `fix:`                            | patch |
| `feat!:` or `BREAKING CHANGE:` footer | major |
| `chore:`, `docs:`, `ci:`, `test:`, `refactor:` | none  |

Examples:

```
feat: add go.mod ecosystem support
fix: handle empty requirements.txt without crashing
feat!: require jq 1.7+ (drops 1.6 compat)
```

## PR checklist

See [`.github/PULL_REQUEST_TEMPLATE.md`](.github/PULL_REQUEST_TEMPLATE.md) — it's auto-applied when you open a PR. Fill every box.

## Release flow

1. Merges to `main` trigger release-please via GitHub Actions.
2. release-please opens (or updates) a release PR that bumps `version.txt` and `.claude-plugin/plugin.json`, and updates `CHANGELOG.md` based on the commits since the last tag.
3. Merging that release PR cuts the git tag and publishes the release.

You don't need to hand-edit `CHANGELOG.md`, `version.txt`, or `plugin.json` — release-please owns them.

## Security

Found a bypass, false-negative, or other issue in the block logic? **Please don't file a public issue.** Open a private [GitHub Security Advisory](https://github.com/DanyItNerd/version-sentinel/security/advisories/new) instead so we can coordinate a fix before disclosure.
