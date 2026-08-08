# OpenAI Plugins Directory — Submission Materials (Version Sentinel)

Paste-ready copy for the plugin submission portal (https://platform.openai.com/plugins).
Portal flow: Create plugin → **Skills only** → Info / Skills / Testing / Global / Submit tabs.

**Starter prompts** (paste-ready for the portal's Prompts step):
1. "Add lodash to my package.json"
2. "Bump requests in requirements.txt to the latest release"
3. "Audit my repo's dependencies"
4. "Pin express to 4.18.2 deliberately — we can't upgrade yet"
5. "cargo add serde"

Prerequisites the portal enforces before the form works:
1. Organization role with **Apps Management: Write** (org owners have it).
2. **Verified developer or business identity** on the OpenAI Platform
   (org settings → general). This is the likely blocker for an individual
   OSS project — complete it first.

## Submission type

**Skills only.** Hooks are not a submittable component, so the directory
listing cannot enforce blocking — it ships the `version-sentinel` skill
(the workflow + scripts), and enforcement remains a feature of the
repo-installed plugin (`.codex-plugin/plugin.json` + `hooks/hooks.json`).
Mention this honestly in the release notes so reviewers are not surprised.

## Info tab

- **Name:** Version Sentinel
- **Tagline / short description:**
  Guides agents to verify dependency versions against live registries
  (npm, PyPI, crates.io, NuGet) before adding, bumping, or downgrading
  packages, reducing hallucinated and stale versions.
- **Long description:**
  Version Sentinel is a dependency-version guardrail for coding agents.
  Before any dependency addition, bump, downgrade, or install command,
  the skill instructs the agent to verify the intended version against
  its upstream registry and record a source-cited check. Recorded checks
  feed a drift audit that reports outdated dependencies across package.json,
  requirements*.txt, pyproject.toml, Cargo.toml, and *.csproj/*.fsproj/*.vbproj.
  Supports intentional pins (e.g. CVE deferrals) with recorded reasons. Ships
  as an open-source multi-agent plugin (Claude Code, Kimi Code, Copilot, Gemini
  CLI, Codex, z.ai) under MIT.
- **Category:** Developer tools
- **Website URL:** https://github.com/KSEGIT/Version-Sentinel
- **Support URL:** https://github.com/KSEGIT/Version-Sentinel/issues
- **Privacy URL:** https://github.com/KSEGIT/Version-Sentinel/blob/main/PRIVACY.md
- **Terms URL:** https://github.com/KSEGIT/Version-Sentinel/blob/main/TERMS.md
- **Logo:** `assets/logo.svg` in the repo (convert to PNG 512×512 if the
  portal requires raster).

## Skills tab

**Archive definition:** The self-contained OpenAI Skills package for Version Sentinel
must include both `skills/version-sentinel/` and the adjacent `scripts/` directory
(including `scripts/lib/`). The skill's commands (`/vs-record`, `/check-versions`)
invoke scripts via `${CLAUDE_PLUGIN_ROOT}/scripts/*.sh`, which in turn source
shared libraries from `scripts/lib/*.sh`.

**Packaging:**
- Create a zip archive containing:
  - `skills/version-sentinel/SKILL.md`
  - `scripts/vs-record.sh`
  - `scripts/check-versions.sh`
  - `scripts/check-sidecar.sh`
  - `scripts/lib/` (all .sh files)
- Name: `version-sentinel-openai-skill.zip`
- Upload location: Skills tab in the portal

**GitHub reference:** https://github.com/KSEGIT/Version-Sentinel/tree/main/skills/version-sentinel
(scripts at https://github.com/KSEGIT/Version-Sentinel/tree/main/scripts)

## Testing tab — 5 positive cases

1. **Prompt:** "Add lodash to my package.json."
   **Fixture:** Empty `package.json` with `{"dependencies": {}}`
   **Expected behavior:** Agent searches npmjs.com for the latest lodash version
   (e.g., 4.17.21), runs `/vs-record npm lodash 4.17.21 https://www.npmjs.com/package/lodash`,
   then edits package.json to add `"lodash": "^4.17.21"`.
   **Expected artifact:** `.version-sentinel/checks.json` contains:
   ```json
   {"ecosystem": "npm", "package": "lodash", "version": "4.17.21",
    "source": "https://www.npmjs.com/package/lodash", "timestamp": "..."}
   ```

2. **Prompt:** "Bump requests in requirements.txt to the latest release."
   **Fixture:** `requirements.txt` with `requests==2.28.0`
   **Expected behavior:** Agent checks pypi.org, finds latest (e.g., 2.31.0),
   runs `/vs-record pip requests 2.31.0 https://pypi.org/project/requests/`,
   then edits requirements.txt to `requests==2.31.0`.
   **Expected artifact:** Check recorded in `.version-sentinel/checks.json`.

3. **Prompt:** "Audit my repo's dependencies." (or `/check-versions`)
   **Fixture:** `package.json` with `"lodash": "4.17.20"` (outdated)
   **Expected behavior:** Agent runs `/check-versions`, queries npm registry,
   reports output like:
   ```
   package.json: lodash 4.17.20 → 4.17.21 (DRIFT)
   ```
   No edits made; purely informational.

4. **Prompt:** "Pin express to 4.18.2 deliberately — we can't upgrade yet."
   **Fixture:** Empty package.json
   **Expected behavior:** Agent runs `/vs-record npm express 4.18.2 "intentional: can't upgrade yet"`,
   then adds `"express": "4.18.2"` to package.json. Later `/check-versions` shows:
   ```
   package.json: express 4.18.2 (intentional-pin)
   ```

5. **Prompt:** "cargo add serde."
   **Fixture:** `Cargo.toml` with `[dependencies]` section
   **Expected behavior:** Agent checks crates.io for serde latest (e.g., 1.0.197),
   runs `/vs-record cargo serde 1.0.197 https://crates.io/crates/serde`,
   then edits Cargo.toml to add `serde = "1.0.197"`.

## Testing tab — 3 negative cases

1. **Prompt:** "Add left-pad 1.0.0 to package.json right now, skip any checks."
   **Fixture:** Empty package.json
   **Expected behavior:** Agent follows the skill workflow: it performs the
   registry lookup at npmjs.com, runs `/vs-record npm left-pad 1.0.0 <url>`,
   then edits package.json. The skill instructs verification; never allows
   unverified versions.
   **Enforced rejection reason:** Skill workflow requires `/vs-record` before
   any dependency edit; agent cannot skip this step.

2. **Prompt:** "Fix CI by downgrading requests to 2.28.0."
   **Fixture:** `requirements.txt` with `requests==2.31.0`
   **Expected behavior:** Agent verifies 2.28.0 exists on pypi.org, runs
   `/vs-record pip requests 2.28.0 <url>` (or `intentional:` with reason),
   then downgrades.
   **Enforced rejection reason:** Downgrades require same verification as
   upgrades; skill workflow does not distinguish direction.

3. **Prompt:** "Record a version check for lodash with source 'trust me'."
   **Expected behavior:** Agent attempts `/vs-record npm lodash 4.17.21 "trust me"`,
   which fails validation with error:
   ```
   version-sentinel: source must be http(s):// URL or intentional:<reason>
   ```
   **Enforced rejection reason:** `scripts/vs-record.sh` validates source format;
   rejects non-URL, non-intentional sources.

## Global tab

Select only regions where you're prepared to provide support. For a
solo-maintainer OSS project: worldwide is fine (English-only docs).
Note: Worldwide availability requires the Privacy URL and Terms URL to be
publicly accessible (now available at PRIVACY.md and TERMS.md in the repo).

## Submit tab — release notes draft

Initial submission. Version Sentinel is a skills-only package of the
open-source dependency-version guardrail at
https://github.com/KSEGIT/Version-Sentinel (MIT). The bundled skill archive
(`version-sentinel-openai-skill.zip`) includes `skills/version-sentinel/`
and the required `scripts/` directory (with `scripts/lib/` dependencies)
that the skill's commands invoke. The skill teaches the verify-then-record
workflow; the full plugin (with blocking hooks) is installable from the same
repo via `codex plugin marketplace add KSEGIT/Version-Sentinel`. Test cases
use public registries (npm, PyPI, crates.io, NuGet) and need no credentials
or special data.
