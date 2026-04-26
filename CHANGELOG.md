# Changelog

All notable changes to version-sentinel.

## [0.3.0](https://github.com/KSEGIT/Version-Sentinel/compare/version-sentinel-v0.2.1...version-sentinel-v0.3.0) (2026-04-26)


### Features

* **docs:** add CLAUDE.md for project overview and structure ([26aedf1](https://github.com/KSEGIT/Version-Sentinel/commit/26aedf1707fbd57260c116210d16acfb2f9162e4))


### Bug Fixes

* **.gitignore:** update patterns to ignore additional files and directories ([c49f4f5](https://github.com/KSEGIT/Version-Sentinel/commit/c49f4f508929918ef09765e0b3bafb04835d42e9))
* **marketplace:** add schema, description, version, category for crawler discovery ([ea32716](https://github.com/KSEGIT/Version-Sentinel/commit/ea3271676f55aa67e9df814a83e2ec4b2672f204))

## [0.2.1](https://github.com/KSEGIT/Version-Sentinel/compare/version-sentinel-v0.2.0...version-sentinel-v0.2.1) (2026-04-22)


### Bug Fixes

* **marketplace:** use relative source to avoid SSH clone ([b922e84](https://github.com/KSEGIT/Version-Sentinel/commit/b922e84a1dcb09cb8145d653361689c6daf6f363))

## [0.2.0](https://github.com/KSEGIT/Version-Sentinel/compare/version-sentinel-v0.1.0...version-sentinel-v0.2.0) (2026-04-22)


### Features

* add GitHub Actions workflow for running tests ([ac895c9](https://github.com/KSEGIT/Version-Sentinel/commit/ac895c99c9548db38cc6234cfd1148d89605a726))
* add initial project structure and configuration files ([34f775b](https://github.com/KSEGIT/Version-Sentinel/commit/34f775b062010d934baad5b5ab7d884bdcfc870f))
* check-sidecar.sh — exit-2 block with stderr for Claude ([d79bb9d](https://github.com/KSEGIT/Version-Sentinel/commit/d79bb9d4f84119d6bf1922db8691cda5e4120422))
* **cmd:** /check-versions audit + registries.sh ([bc98c29](https://github.com/KSEGIT/Version-Sentinel/commit/bc98c2932ff7c860554e3b8cc84aa6664877bba4))
* **cmd:** /vs-record slash command + shell backend ([4bfbaf6](https://github.com/KSEGIT/Version-Sentinel/commit/4bfbaf625d921c6c0a1ba0b2bce37bb1286a04dc))
* **hook:** detect-install-cmd.sh (Bash install commands) ([cddb1ee](https://github.com/KSEGIT/Version-Sentinel/commit/cddb1eea0494326a4a042427a6f922979b50ae2b))
* **hook:** detect-manifest-edit.sh (Edit|Write|MultiEdit) ([0174255](https://github.com/KSEGIT/Version-Sentinel/commit/0174255bf28f99b9f695c8d1f8ea351ec11d367b))
* **hook:** wire hooks.json (Edit|Write|MultiEdit + Bash matchers) ([db64f0e](https://github.com/KSEGIT/Version-Sentinel/commit/db64f0e6940484b639c4b1f6ea3b955ad5acc412))
* **lib:** sidecar read/write with dedupe + auto-gitignore ([8065e5c](https://github.com/KSEGIT/Version-Sentinel/commit/8065e5c00e884939fcf600ebaddcee3bbb121465))
* **parse:** Cargo.toml parser (path/git deps skipped) ([4ca3b57](https://github.com/KSEGIT/Version-Sentinel/commit/4ca3b57d4bf16a92746f596af168bb5fdfd2fd5c))
* **parse:** csproj/fsproj/vbproj PackageReference parser ([0880fee](https://github.com/KSEGIT/Version-Sentinel/commit/0880fee72ad6af0cecf55b4e1b14fd5dfc3b8a75))
* **parse:** install-command parser (npm/pip/cargo/dotnet) ([ecf11b1](https://github.com/KSEGIT/Version-Sentinel/commit/ecf11b1b493a93685c37a640f832a40a4e254e0d))
* **parse:** npm package.json parser (all 4 dep sections) ([abb488e](https://github.com/KSEGIT/Version-Sentinel/commit/abb488e12ea1164a7fb16bf408d4d96a6dc8829b))
* **parse:** path→ecosystem dispatch + manifest-set diff ([5f0503f](https://github.com/KSEGIT/Version-Sentinel/commit/5f0503fac7cd02769f0753aad0e778aab72f806b))
* **parse:** pip requirements.txt parser ([085b15f](https://github.com/KSEGIT/Version-Sentinel/commit/085b15f618a004aea3fe16ab1fe4167dd8b5624f))
* **parse:** pyproject.toml parser (PEP 621 + Poetry + uv) ([0954cbd](https://github.com/KSEGIT/Version-Sentinel/commit/0954cbd2e254f17bfa80513e6855cc887dbd1313))
* plugin hardening, release automation, CI matrix ([8437b9a](https://github.com/KSEGIT/Version-Sentinel/commit/8437b9ad67b52bb97941829aeee0beeff8caa04c))
* plugin hardening, release automation, CI matrix ([da28515](https://github.com/KSEGIT/Version-Sentinel/commit/da28515354fa88c33353a30102d23269bc65fad9))
* **scaffold:** plugin.json + marketplace.json + LICENSE ([8d99c34](https://github.com/KSEGIT/Version-Sentinel/commit/8d99c34569cefa798982a41a282e94b43144d46a))
* **skill:** version-sentinel SKILL.md workflow guide ([71712e8](https://github.com/KSEGIT/Version-Sentinel/commit/71712e8990aa254228f1ebfde84b24cea82623f8))


### Bug Fixes

* address CodeRabbit review feedback ([13dabc0](https://github.com/KSEGIT/Version-Sentinel/commit/13dabc0464357d22d9c121461b4267ab7fd76b2a))
* **ci:** macOS bash 3.2 compat + shellcheck severity ([722e0af](https://github.com/KSEGIT/Version-Sentinel/commit/722e0af57e564482eaf03c45d07e37d705448911))
* **lib:** guard sidecar write against jq failure + test robustness ([443be3f](https://github.com/KSEGIT/Version-Sentinel/commit/443be3fba44c8626cfb4ea8c50d872de8dfaa36d))
* run.sh integration smoke path (cwd-relative after cd) ([2e77ea1](https://github.com/KSEGIT/Version-Sentinel/commit/2e77ea19a2346e676b1aa6e1fb1d092411a6b277))

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
