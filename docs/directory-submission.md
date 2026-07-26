# Plugin Directory Submission — Version Sentinel

> Note: since this copy was drafted, the plugin was ported to six agent platforms (multi-agent support, v0.4.0). This file remains the Anthropic-form copy; all other platforms' distribution channels are tracked in `docs/marketplaces.md`.

Draft copy for the Anthropic plugin directory submission form (Plugin details step).

---

## Plugin name

```
Version Sentinel
```

Notes: Matches `plugin.json` (`version-sentinel`) and the GitHub repo. Contains no third-party brand names — registry/ecosystem names (npm, PyPI, etc.) appear only in description/keywords.

---

## Plugin description

### Short (≈180 chars)

```
Hard-blocks dependency additions, bumps, and downgrades in Claude Code until a fresh, source-cited version check is recorded. Supports npm, pip, Poetry/uv, Cargo, and NuGet.
```

### Medium (recommended)

```
Version Sentinel is a PreToolUse guardrail that refuses dependency edits and install commands until Claude has verified the package version against its upstream registry and recorded the citation. It stops hallucinated versions, stale training-data pins, silent downgrades, and compromised-release installs from reaching your manifest. Supports package.json (npm/pnpm/yarn/bun), requirements.txt / pyproject.toml (pip, Poetry, uv), Cargo.toml, and .csproj/.fsproj/.vbproj. Includes /vs-record to log a check, /check-versions to audit existing manifests, and a version-reviewer subagent. Escape hatches exist for intentional old-version pins, private registries, and offline sessions.
```

---

## Example use cases

```
Example 1: Claude tries to add "lodash": "^4.17.21" to package.json from memory. Version Sentinel blocks the Edit with exit 2, Claude runs WebSearch against npmjs.com, calls /vs-record npm lodash <latest> <url>, then retries — and the write succeeds with an audit trail.

Example 2: An agent runs `pip install requests==2.28.0` to "fix" a failing CI job by downgrading. The Bash PreToolUse hook refuses the install until a fresh PyPI check is on record, preventing a silent regression to a vulnerable build.

Example 3: You ask Claude to bump every dependency in a Rust workspace. Running /check-versions audits Cargo.toml against crates.io and reports drift before any edit is attempted, so the upgrade plan is grounded in current registry data instead of training-cutoff guesses.

Example 4: You intentionally want to stay on an older pin (e.g. deferring a CVE fix). You run /vs-record npm <pkg> 1.0.0 "intentional: CVE fix deferred" once — subsequent edits to that pin pass the hook without re-checking.
```
