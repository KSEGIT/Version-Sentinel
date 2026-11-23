# Plugin Directory Submission — Version Sentinel

> Note: since this copy was drafted, the plugin was ported to six agent platforms (multi-agent support, v0.3.0). This file remains the Anthropic-form copy; all other platforms' distribution channels are tracked in `docs/marketplaces.md`.

Draft copy for the Anthropic plugin directory submission form (Plugin details step).

---

## Plugin name

```
Version Sentinel
```

Notes: Matches `plugin.json` (`version-sentinel`) and the GitHub repo. Contains no third-party brand names — registry/ecosystem names (npm, PyPI, etc.) appear only in description/keywords.

---

## Website URL

```
https://ksegit.github.io/Version-Sentinel/
```

---

## Plugin description

### Short (≈180 chars)

```
Warns about dependency version checks in Claude Code without blocking tools. Supports npm, pip, Poetry/uv, Cargo, and NuGet.
```

### Medium (recommended)

```
Version Sentinel provides advisory PreToolUse warnings and recommends checking package versions against upstream registries. It helps identify hallucinated versions, stale pins, and unexplained downgrades. Hooks always allow tools. Supports package.json (npm/pnpm/yarn/bun), requirements.txt / pyproject.toml (pip, Poetry, uv), Cargo.toml, and .csproj/.fsproj/.vbproj. Includes /vs-record to log a check, /check-versions to audit existing manifests, and a version-reviewer subagent. Failed checks, private registries, and offline sessions remain allowed and are reported truthfully.
```

---

## Example use cases

```
Example 1: Claude tries to add "lodash": "^4.17.21" to package.json from memory. Version Sentinel warns and allows the Edit. Claude can check npmjs.com and use /vs-record to save truthful evidence.

Example 2: An agent runs `pip install requests==2.28.0` to "fix" a failing CI job by downgrading. The Bash PreToolUse hook warns about missing version evidence and allows the install. A PyPI check can help assess the chosen version.

Example 3: You ask Claude to bump every dependency in a Rust workspace. Running /check-versions audits Cargo.toml against crates.io and reports drift before any edit is attempted, so the upgrade plan is grounded in current registry data instead of training-cutoff guesses.

Example 4: You intentionally want to stay on an older pin (e.g. deferring a CVE fix). You run /vs-record npm <pkg> 1.0.0 "intentional: CVE fix deferred" once — the reason appears in later audits. All edits remain allowed.
```
