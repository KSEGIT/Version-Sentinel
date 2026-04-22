# Changelog

All notable changes to version-sentinel.

## [Unreleased]

### Added
- `userConfig` block in `plugin.json` for `disable` (bool) and `window_hours` (number). Values exported to scripts as `CLAUDE_PLUGIN_OPTION_*` and mapped onto legacy `VS_DISABLE` / `VS_WINDOW_HOURS` by `scripts/lib/options.sh`. Shell env vars still win.
- `homepage` field in `plugin.json`.
- `SessionStart` hook running `scripts/prereq-check.sh` — warns on missing `jq` / `curl` / `python3`. Non-blocking (always exits 0).
- `PostToolUse:Bash` hook running `scripts/auto-record.sh` — auto-inserts a sidecar entry tagged `auto-recorded:` when a recognised install command finishes successfully.
- `bin/vs-record` thin wrapper exposing `/vs-record` as a bare command via the plugin `bin/` PATH.
- Stricter arg validation in `scripts/vs-record.sh`: ecosystem whitelist, version shape check, package-name `/` rule (npm `@scope/name` still allowed).
- `agents/version-reviewer.md` — read-only pre-release subagent that runs `/check-versions` and produces a structured DRIFT / intentional-pin / lookup-failed report.
- `CONTRIBUTING.md` — local setup, test commands, how-to-add-an-ecosystem checklist, Conventional Commits guide.
- `release-please` workflow with `release-type: simple`; bumps `version.txt`, `.release-please-manifest.json`, `.claude-plugin/plugin.json` `$.version`, and `CHANGELOG.md`.
- `changelog-check` workflow: fails PRs that bump version without updating `CHANGELOG.md`.
- `tests` workflow extended to 3-OS matrix (Ubuntu / macOS / Windows), plus manifest-validate and shellcheck jobs. All GitHub Actions pinned to commit SHAs.
- `.github/dependabot.yml` — weekly updates for GitHub Actions.
- `.github/ISSUE_TEMPLATE/` (bug / feature / config) and `.github/PULL_REQUEST_TEMPLATE.md`.
- 4 new test files covering `options.sh` mapping, `vs-record` validation, prereq check, and auto-record.

### Changed
- `marketplace.json` no longer pins `version` — single source of truth is `plugin.json`.

## [0.1.0] — 2026-04-17

### Added
- PreToolUse hooks for `Edit`, `Write`, `MultiEdit`, and `Bash` tools.
- Manifest parsers for 5 ecosystem file families: `package.json`, `requirements*.txt` / `constraints*.txt`, `pyproject.toml` (PEP 621 + Poetry + uv), `Cargo.toml`, `*.csproj` / `*.fsproj` / `*.vbproj`.
- Install-command parsers for `npm`/`pnpm`/`yarn`/`bun`, `pip`/`pip3`, `poetry`, `uv`, `cargo`, `dotnet`.
- `/vs-record` slash command to write sidecar entries (accepts `http(s)://` URLs or `intentional:` reasons).
- `/check-versions` slash command to audit all manifests against upstream registries (npm, PyPI, NuGet, crates.io).
- Sidecar state at `<cwd>/.version-sentinel/checks.json` with auto-gitignore and last-write-wins dedupe on `(ecosystem, pkg)`.
- `VS_DISABLE=1` escape hatch and `.version-sentinel/ignore` pattern file.
- Fail-open philosophy: any hook-internal error (missing `jq`/`curl`, parse crash, unreadable pre-edit file) passes through rather than blocking Claude.
- Bash test harness with 14+ fixture-driven unit tests + 1 integration smoke.

### Known limitations
- `<PackageReference>` with a child `<Version>` element (rather than attribute) is not parsed. Attribute form only.
- `pyproject.toml` range specifiers (e.g. `>=1,<2`) are reduced to the lower bound.
- Offline use: `/check-versions` requires network; hook blocks still work without it.
- Claude obedience: v0.1 trusts the model to actually search before invoking `/vs-record`. v0.2 will probe the transcript.

### Roadmap
- v0.2.0: `go.mod`, `Gemfile`, `composer.json`; transcript-probe honesty check.
- v0.3.0: Maven `pom.xml`, Gradle `build.gradle(.kts)`, legacy Python (`Pipfile`, `setup.py`, `setup.cfg`).
- v1.0.0: all 11 file families + stable sidecar schema guarantee.
