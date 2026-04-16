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

1. Claude cannot add, bump, or downgrade a dependency in any of the 11 covered ecosystem file families without sidecar proof.
2. Sidecar proof requires a valid source recorded via `/vs-record`: either an `http(s)://` URL OR a string prefixed `intentional:` documenting the reason for a non-latest pin.
3. `/check-versions` audits the manifest in the current working directory, reports drift, runs offline-safe.
4. Plugin installs via the documented two-step flow:
   ```
   /plugin marketplace add <user>/version-sentinel
   /plugin install version-sentinel@version-sentinel-marketplace
   ```
   (The `@<marketplace-name>` suffix references `marketplace.json`'s `name` field, not the GitHub repo.)
5. Plugin fails open on any internal error — never bricks Claude.

## Architecture

```
version-sentinel/                          # GitHub repo root
├── .claude-plugin/
│   ├── plugin.json                        # name, version, description, author, repository, license
│   └── marketplace.json                   # required: name, owner, plugins[] (NO $schema field)
├── hooks/
│   └── hooks.json                         # plugin wrapper: {"hooks": {"PreToolUse": [...]}}
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

- `plugin.json` required fields: `name` (kebab-case). `version` recommended (some validators reject missing). Optional: `description`, `author{name,email,url}`, `homepage`, `repository`, `license`, `keywords`. Default component paths (`hooks/`, `skills/`, `commands/`) load without explicit pointers.
- `hooks/hooks.json` (plugin form) uses the documented wrapper: `{"hooks": {"PreToolUse": [...]}}`. NO `description` field (not in documented schema — may be ignored or rejected). Differs from user `settings.json` which places events at top level.
- `marketplace.json` required fields: `name` (marketplace name — becomes the `@<marketplace-name>` suffix at install), `owner` (`{name, email?, url?}`), `plugins[]` (each entry needs `name` + `source`, e.g. `{"source":"github","repo":"<user>/version-sentinel"}`). NO `$schema` field — not documented. Our marketplace `name` will be `version-sentinel-marketplace` to disambiguate from the plugin name itself.
- Hook commands reference scripts as `${CLAUDE_PLUGIN_ROOT}/scripts/<name>.sh` for portability.
- **Hook matcher must include `MultiEdit`**: `"matcher": "Edit|Write|MultiEdit"`. Claude's built-in MultiEdit tool applies multiple string swaps in one call and would otherwise bypass the manifest-edit hook.
- **Block signalling**: use **exit 2** with stderr content (the documented hard-block path). The stderr text is surfaced to the model verbatim. Do not rely on `stopReason` (that is a JSON-output field for a different control path). If JSON output is used in future, the field is `hookSpecificOutput.permissionDecisionReason`.

### State

- **Sidecar (primary):** `<cwd>/.version-sentinel/checks.json` — project-local, survives plugin updates, lives with the code it gates.
- **Sidecar (fallback):** `${CLAUDE_PLUGIN_DATA}/checks.json` (resolves to `~/.claude/plugins/data/<plugin-id>/checks.json`, the documented per-plugin persistent data dir) — used only when cwd is outside any writable project root.
- **Auto-gitignore:** on first write, the sidecar directory auto-creates `.version-sentinel/.gitignore` containing `*\n!.gitignore` so user repos never accidentally commit the state file. Idempotent — only created when missing.
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
- **Dedupe rule:** entries are keyed by `(ecosystem, pkg)` — appending a new entry for an existing key replaces the prior one (last-write-wins). Prevents unbounded growth.
- **Freshness window:** 24 hours per `(ecosystem, pkg, version)` tuple. A different version in a subsequent attempt requires a new check (old entry is overwritten by the new version's record).

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

Hook computes a pkg-set diff between pre-edit and post-edit manifest contents. Trigger block when: (a) a dependency is newly added, (b) its version string changes (bump OR downgrade — both require a fresh check to confirm intent against current latest). Removals and unchanged entries = passthrough (exit 0).

**Input reconstruction per tool:**

| Tool | Pre-edit source | Post-edit source |
|------|-----------------|------------------|
| `Edit` (single-occurrence) | Read file from disk, apply `old_string`→`new_string` conceptually, or just diff `old_string` vs `new_string` directly when only one occurrence | `new_string` |
| `Edit` with `replace_all: true` | **Unsafe for naive string-swap diff** (multi-hit). Hook must read full file from disk, simulate `s/old/new/g`, then diff pre vs simulated post as whole-manifest parse. |
| `Write` | Read file from disk (may be missing — then all deps in `content` are treated as "newly added") | `tool_input.content` |
| `MultiEdit` | Read file from disk, apply each edit in order to an in-memory copy, diff pre vs simulated post | simulated post |

If the hook cannot read the pre-edit file (permission, path), it fails open with a stderr note — it does not block on read failure.

### `/check-versions` audit registries

- npm: `https://registry.npmjs.org/<pkg>` — pick `dist-tags.latest`
- PyPI: `https://pypi.org/pypi/<pkg>/json` — pick `info.version`
- NuGet: `https://api.nuget.org/v3-flatcontainer/<pkg-lower>/index.json` — pick last element of `versions[]` (sorted ascending)
- crates.io: `https://crates.io/api/v1/crates/<pkg>` — pick `crate.max_stable_version`
- Go: `https://proxy.golang.org/<module>/@latest` — pick `.Version`. **Module-path escape rule:** every uppercase letter in the module path must be prefixed with `!` and lowercased (e.g. `github.com/Masterminds/squirrel` → `github.com/!masterminds/squirrel`). Implementation must escape before request.
- RubyGems: `https://rubygems.org/api/v1/gems/<pkg>.json` — pick `.version`
- Packagist: `https://repo.packagist.org/p2/<pkg>.json` — pick first entry of `packages.<pkg>[].version`
- Maven Central: `https://repo1.maven.org/maven2/<groupId-slashed>/<artifactId>/maven-metadata.xml` — parse `<versioning><latest>` (preferred; the `search.maven.org/solrsearch` endpoint is undocumented/unstable and must NOT be used)

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

1. **`/vs-record` with `intentional:` source** — records pin reason, passes hook, surfaces as warning (not error) in `/check-versions`. Also the documented escape for users in regions where WebSearch is unavailable (tool is US-only per Anthropic docs) — `intentional: no-websearch-region` is an accepted reason; users may instead cite a `WebFetch`ed registry URL or a context7 lookup result.
2. **`VS_DISABLE=1` env var** — hook exits 0 if set. For throwaway sessions.
3. **`.version-sentinel/ignore` file** — newline-delimited `ecosystem:pkg` patterns (globs OK, e.g. `npm:@internal/*`). Read by `check-sidecar.sh`.

### Allowed proof-source URLs

`/vs-record` validates the source argument:
- `http(s)://` URL → always accepted (expected path: WebSearch / WebFetch / context7 output)
- `intentional:<reason>` → accepted, recorded as pinned intent
- Anything else → command rejects, prints usage

Relying on any single tool (WebSearch) would brick non-US users. The accepted-source list explicitly includes WebFetch and context7 outputs.

### Fail-open philosophy

Any hook-internal error (missing dependency tool, parse crash) passes through rather than bricking Claude. `/check-versions` surfaces quiet slippage on demand.

## Testing

- **Script-level unit tests:** `tests/` directory with fixture JSONs (sample `tool_input` payloads). Each script runs against fixture, asserts exit code + stderr content. Run via `bash tests/run.sh` — no framework.
- **Integration:** `claude --plugin-dir C:/Users/DanielKiska/Source/private/version-sentinel` load, trigger Edit on a fixture `package.json`, verify block produced the expected exit-2 + stderr message seen by Claude. `/reload-plugins` on script changes.
- **Registry-API tests:** `/check-versions` live-network tests gated by `VS_LIVE=1` env var — skipped in CI, run on-demand locally.

## Risks + Mitigations

| Risk | Mitigation |
|------|------------|
| Claude fakes sidecar without real WebSearch | v0.1: `/vs-record` requires a valid URL or `intentional:` reason; SKILL.md instructs honest flow — relies on model obedience. v0.2 planned: transcript-probe (see below) |
| Hook slow on large Bash commands | Parsers use fast regex, short-circuit on first match; target <100 ms per invocation |
| Registry API rate limits | `/check-versions` sequential with 200 ms throttle, no caching |
| User on Windows lacks `jq`/`curl` | README requires Git Bash (ships both) or `choco install jq curl`; fail-open if missing |
| WebSearch unavailable (non-US region) | `/vs-record` also accepts WebFetch URLs, context7 output URLs, and `intentional: no-websearch-region` |

### Planned hardening (v0.2): transcript probe

PreToolUse hooks receive a `transcript_path` field on stdin — the path to the current session's JSONL transcript. After the blocking exit-2 and the subsequent retry, the hook can `grep` the last N transcript entries for a `WebSearch` / `WebFetch` / `context7` tool_use whose arguments mention the package being installed. Record-present-without-query becomes detectable.

Not bulletproof (Claude could query for the right string without reading it), but raises the bar substantially over pure model obedience. Deferred to v0.2 because: (a) v0.1 needs to prove the block/record/retry loop works before adding validation layers, (b) transcript format stability is not yet confirmed.

## Release Plan

| Version | Ecosystems |
|---------|-----------|
| v0.1.0 | npm, pip, pyproject.toml, Cargo.toml, csproj (5 ecosystems) |
| v0.2.0 | + go.mod, Gemfile, composer.json |
| v0.3.0 | + Maven, Gradle, legacy Python (Pipfile, setup.py, setup.cfg) |
| v1.0.0 | All 11 covered + stable sidecar schema |

## Open Questions

None at spec approval. Implementation plan (next phase) will expand per-ecosystem parser details and test fixtures.
