# version-sentinel — Design Spec

**Date:** 2026-04-16
**Status:** Approved (brainstorming phase complete)
**Next step:** writing-plans skill → implementation plan

---

## Goal

Prevent Claude Code from adding or bumping package dependencies in any supported ecosystem without a fresh, WebSearch-verified latest-version check. Enforce via PreToolUse hard block (exit 2) that only unblocks after Claude records the check in a project-local sidecar file.

## Non-Goals

- Not a security/CVE scanner.
- Not a license compliance tool.
- Not a lockfile reconciler (ignores `package-lock.json`, `Pipfile.lock`, etc.).
- Does not enforce "use latest" — user may pin old versions intentionally via escape hatch.
- Not a replacement for context7 MCP — version-sentinel checks versions, context7 fetches docs.

## Success Criteria

1. Claude cannot add or bump a dependency in any of the 13 covered ecosystems without sidecar proof.
2. Sidecar proof requires a source URL recorded via `/vs-record`.
3. `/check-versions` audits the manifest in the current working directory, reports drift, runs offline-safe.
4. Plugin installs via `/plugin install version-sentinel@<user>/version-sentinel` directly from GitHub.
5. Plugin fails open on any internal error — never bricks Claude.

## Architecture

```
version-sentinel/                          # GitHub repo root
├── .claude-plugin/
│   ├── plugin.json                        # name, version, description, author, repository, license
│   └── marketplace.json                   # $schema + 1-plugin marketplace entry
├── hooks/
│   └── hooks.json                         # plugin wrapper format: {description, hooks: {PreToolUse: [...]}}
├── scripts/
│   ├── detect-manifest-edit.sh            # Edit|Write handler
│   ├── detect-install-cmd.sh              # Bash handler
│   ├── check-sidecar.sh                   # shared allow/block decision
│   └── lib/
│       ├── parse-manifest.sh              # per-ecosystem manifest parsers
│       └── parse-install-cmd.sh           # per-ecosystem install-cmd regex
├── commands/
│   ├── vs-record.md                       # /vs-record <pkg> <version> <source-url>
│   └── check-versions.md                  # /check-versions — full manifest audit
├── skills/
│   └── version-sentinel/
│       └── SKILL.md                       # workflow + WebSearch query templates
├── tests/
│   ├── fixtures/                          # sample tool_input JSON payloads
│   └── run.sh                             # bash test runner (no framework)
├── README.md
└── LICENSE
```

### Schema compliance (verified against official docs 2026-04-16)

- `plugin.json` required fields: `name` (kebab-case), `version` (semver, enforced by validator). Optional: `description`, `author{name,email,url}`, `homepage`, `repository`, `license`, `keywords`. Default component paths (`hooks/`, `skills/`, `commands/`) load without explicit pointers.
- `hooks/hooks.json` (plugin form) uses wrapper: `{"description": "...", "hooks": {"PreToolUse": [...]}}` — different from user `settings.json` which places events at top level.
- `marketplace.json`: `$schema: https://anthropic.com/claude-code/marketplace.schema.json`. Plugins array entries need `name` + `source` (e.g. `{"source":"github","repo":"<user>/version-sentinel"}`).
- Hook commands reference scripts as `${CLAUDE_PLUGIN_ROOT}/scripts/<name>.sh` for portability.

### State

- **Sidecar (primary):** `<cwd>/.version-sentinel/checks.json` — project-local, user adds to `.gitignore`.
- **Sidecar (fallback):** `~/.claude/version-sentinel/checks.json` — for non-repo working directories.
- **Schema:**
  ```json
  {
    "entries": [
      {
        "ecosystem": "npm",
        "pkg": "lodash",
        "version": "4.17.21",
        "source": "https://www.npmjs.com/package/lodash",
        "checkedAt": "2026-04-16T14:22:00Z"
      }
    ]
  }
  ```
- **Freshness window:** 24 hours per `pkg@version` pair. Different version in subsequent attempt = new check required.

## Data Flow

1. Claude invokes `Edit` on `package.json` adding `"lodash": "^4.17.21"` (or `Bash: npm install lodash`).
2. PreToolUse hook fires → `detect-manifest-edit.sh` or `detect-install-cmd.sh`.
3. Parser extracts `ecosystem=npm`, `pkg=lodash`, `version=4.17.21`.
4. `check-sidecar.sh` reads sidecar JSON.
5. No matching fresh entry → **exit 2** with stderr:
   ```
   BLOCKED: version-sentinel.
   Package: lodash (npm). Version in manifest: 4.17.21.
   No fresh version check on record.

   REQUIRED before retry:
   1. Run WebSearch: "lodash latest version site:npmjs.com"
   2. Invoke /vs-record lodash <latest-version-from-search> <url-from-search>
   3. Retry your edit/install.
   ```
6. Claude reads block → WebSearch → invokes `/vs-record lodash 4.17.21 https://www.npmjs.com/package/lodash`.
7. Slash command appends entry to sidecar.
8. Claude retries → hook re-fires → sidecar hit → fresh → **exit 0** → passes.

## Ecosystem Coverage

### Manifest detection (Edit|Write trigger)

| Ecosystem | File pattern | Parser extracts |
|-----------|--------------|-----------------|
| npm/pnpm/yarn/bun | `package.json` | diff `dependencies`, `devDependencies`, `peerDependencies`, `optionalDependencies` |
| Python (pip) | `requirements*.txt`, `constraints*.txt` | line-by-line `pkg==ver` / `pkg>=ver` |
| Python (modern) | `pyproject.toml` | `[project.dependencies]`, `[tool.poetry.dependencies]`, `[tool.uv]` |
| Python (legacy) | `Pipfile`, `setup.py`, `setup.cfg` | best-effort regex |
| .NET | `*.csproj`, `*.fsproj`, `*.vbproj`, `packages.config`, `Directory.Packages.props` | `<PackageReference Include="X" Version="Y" />` |
| Rust | `Cargo.toml` | `[dependencies]`, `[dev-dependencies]`, `[build-dependencies]` |
| Go | `go.mod` | `require` blocks |
| Ruby | `Gemfile`, `*.gemspec` | `gem "X", "Y"` |
| PHP | `composer.json` | `require`, `require-dev` |
| Java (Maven) | `pom.xml` | `<dependency><artifactId>…<version>` |
| Java (Gradle) | `build.gradle`, `build.gradle.kts` | `implementation "group:artifact:version"` |

### Install-cmd detection (Bash trigger, regex in `tool_input.command`)

```
(npm|pnpm|yarn|bun)\s+(add|install|i)\s+(?!-)(\S+)
pip(3)?\s+install\s+(?!-)(\S+)
poetry\s+add\s+(\S+)
uv\s+(add|pip install)\s+(\S+)
dotnet\s+add\s+package\s+(\S+)
nuget\s+install\s+(\S+)
cargo\s+add\s+(\S+)
go\s+get\s+(?!-)(\S+)
gem\s+install\s+(\S+)
composer\s+require\s+(\S+)
mvn\s+.*-Dartifact=(\S+)
```

### Diff strategy (manifest edits)

Hook computes pkg-set diff between `tool_input.old_string` vs `new_string` (Edit) or before-disk vs `new` (Write). Only **newly added** or **version-bumped** deps trigger block. Removals + unchanged = passthrough.

### `/check-versions` audit registries

- npm: `https://registry.npmjs.org/<pkg>`
- PyPI: `https://pypi.org/pypi/<pkg>/json`
- NuGet: `https://api.nuget.org/v3-flatcontainer/<pkg-lower>/index.json`
- crates.io: `https://crates.io/api/v1/crates/<pkg>`
- Go: `https://proxy.golang.org/<mod>/@latest`
- RubyGems: `https://rubygems.org/api/v1/gems/<pkg>.json`
- Packagist: `https://repo.packagist.org/p2/<pkg>.json`
- Maven Central: `https://search.maven.org/solrsearch/select`

Sequential with 200 ms throttle. No cache — per-invocation freshness preferred.

## Error Handling

| Case | Behavior |
|------|----------|
| Not a manifest / not an install cmd | Exit 0 silently |
| Manifest edit removes deps only | Exit 0 |
| Version unchanged (formatting/comment edit) | Exit 0 |
| Private registry / local tarball (`file:./…`, `git+https://…`, `workspace:*`) | Exit 0 + stderr note "skipped private/local source" |
| `jq` / `curl` missing | Exit 0 + stderr warning (fail open) |
| Sidecar JSON corrupt | Treat as missing → block + log corruption warning |
| Tool_input JSON unparseable | Exit 0 + stderr log (fail open) |
| Intentional old-version pin | `/vs-record <pkg> <pinned-version> "intentional: <reason>"` — `intentional:` prefix bypasses `/check-versions` mismatch flag |

### Escape hatches

1. **`/vs-record` with `intentional:` source** — records pin reason, passes hook, surfaces as warning (not error) in `/check-versions`.
2. **`VS_DISABLE=1` env var** — hook exits 0 if set. For throwaway sessions.
3. **`.version-sentinel/ignore` file** — newline-delimited `ecosystem:pkg` patterns (globs OK, e.g. `npm:@internal/*`). Read by `check-sidecar.sh`.

### Fail-open philosophy

Any hook-internal error (missing dependency tool, parse crash) passes through rather than bricking Claude. `/check-versions` surfaces quiet slippage on demand.

## Testing

- **Script-level unit tests:** `tests/` directory with fixture JSONs (sample `tool_input` payloads). Each script runs against fixture, asserts exit code + stderr content. Run via `bash tests/run.sh` — no framework.
- **Integration:** `claude --plugin-dir C:/Users/DanielKiska/Source/private/version-sentinel` load, trigger Edit on a fixture `package.json`, verify block with correct stopReason. `/reload-plugins` on script changes.
- **Registry-API tests:** `/check-versions` live-network tests gated by `VS_LIVE=1` env var — skipped in CI, run on-demand locally.

## Risks + Mitigations

| Risk | Mitigation |
|------|------------|
| Claude fakes sidecar without real WebSearch | `/vs-record` requires URL argument; SKILL.md instructs honest flow; not 100% enforceable — relies on model obedience |
| Hook slow on large Bash commands | Parsers use fast regex, short-circuit on first match; target <100 ms per invocation |
| Registry API rate limits | `/check-versions` sequential with 200 ms throttle, no caching |
| User on Windows lacks `jq`/`curl` | README requires Git Bash (ships both) or `choco install jq curl`; fail-open if missing |

## Release Plan

| Version | Ecosystems |
|---------|-----------|
| v0.1.0 | npm, pip, pyproject.toml, Cargo.toml, csproj (5 ecosystems) |
| v0.2.0 | + go.mod, Gemfile, composer.json |
| v0.3.0 | + Maven, Gradle, legacy Python (Pipfile, setup.py, setup.cfg) |
| v1.0.0 | All 13 covered + stable sidecar schema |

## Open Questions

None at spec approval. Implementation plan (next phase) will expand per-ecosystem parser details and test fixtures.
