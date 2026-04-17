# Changelog

All notable changes to version-sentinel.

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
