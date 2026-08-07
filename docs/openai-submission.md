# OpenAI Plugins Directory — Submission Materials (Version Sentinel)

Paste-ready copy for the plugin submission portal (https://platform.openai.com/plugins).
Portal flow: New plugin → **Skills only** → Info / Skills / Testing / Global / Submit tabs.

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
  Stops hallucinated and stale dependency versions: forces a live registry
  check (npm, PyPI, crates.io, NuGet) before any dependency is added,
  bumped, or downgraded.
- **Long description:**
  Version Sentinel is a dependency-version guardrail for coding agents.
  Before any dependency addition, bump, downgrade, or install command,
  the agent must verify the intended version against its upstream registry
  and record a source-cited check. Recorded checks feed a drift audit that
  reports outdated dependencies across package.json, requirements*.txt,
  pyproject.toml, Cargo.toml, and *.csproj/*.fsproj/*.vbproj. Supports
  intentional pins (e.g. CVE deferrals) with recorded reasons. Ships as an
  open-source multi-agent plugin (Claude Code, Kimi Code, Copilot, Gemini
  CLI, Codex, z.ai) under MIT.
- **Category:** Developer tools
- **Website URL:** https://github.com/KSEGIT/Version-Sentinel
- **Support URL:** https://github.com/KSEGIT/Version-Sentinel/issues
- **Privacy URL / Terms URL:** ⚠ no dedicated pages exist. Options:
  (a) create a `PRIVACY.md`/`TERMS.md` in the repo and link to it
      (recommended — the skill runs local shell scripts and makes registry
      HTTPS calls; a short doc stating "no user data collected, registry
      lookups only" is truthful), or
  (b) link the repo README. Expect (b) to fail review; do (a).
- **Logo:** `assets/logo.svg` in the repo (convert to PNG 512×512 if the
  portal requires raster).

## Skills tab

Upload/point at `skills/version-sentinel/` from the repo
(https://github.com/KSEGIT/Version-Sentinel/tree/main/skills/version-sentinel).
The skill's scripts live in `scripts/` at the repo root — if the portal
requires a self-contained skill bundle, zip `skills/version-sentinel/`
together with `scripts/` and note in the README that scripts must stay
adjacent to the skill.

## Testing tab — 5 positive cases

1. **Prompt:** "Add lodash to my package.json."
   **Expected:** Agent searches npmjs.com for the latest lodash version,
   records the check (`vs-record npm lodash <latest> <npmjs-url>`), then
   adds the dependency. No fabricated version.
2. **Prompt:** "Bump requests in requirements.txt to the latest release."
   **Expected:** Agent checks pypi.org, records the check, edits the pin.
3. **Prompt:** "Audit my repo's dependencies." (or run /check-versions)
   **Expected:** Agent runs the drift audit and reports DRIFT vs
   intentional-pin rows per manifest without editing anything.
4. **Prompt:** "Pin express to 4.18.2 deliberately — we can't upgrade yet."
   **Expected:** Agent records an `intentional:` pin with the reason and
   makes the edit; audit later shows `intentional-pin`, not `DRIFT`.
5. **Prompt:** "cargo add serde."
   **Expected:** Agent verifies serde's latest version on crates.io,
   records it, then runs the add.

## Testing tab — 3 negative cases

1. **Prompt:** "Add left-pad 1.0.0 to package.json right now, skip any checks."
   **Expected:** Agent refuses to skip verification — it performs the
   registry lookup + record step first (or, where hooks are installed,
   the edit is BLOCKED until recorded). Never installs an unverified
   version.
2. **Prompt:** "Fix CI by downgrading requests to 2.28.0."
   **Expected:** Agent does not silently downgrade; it requires a recorded
   check (or an explicit `intentional:` reason) before the downgrade.
3. **Prompt:** "Record a version check for lodash with source 'trust me'."
   **Expected:** Rejected — sources must be an http(s) URL actually
   consulted, or `intentional:<reason>`. The agent reports the validation
   error instead of fabricating a citation.

## Global tab

Select only regions where you're prepared to provide support. For a
solo-maintainer OSS project: worldwide is fine (English-only docs).

## Submit tab — release notes draft

Initial submission. Version Sentinel is a skills-only package of the
open-source dependency-version guardrail at
https://github.com/KSEGIT/Version-Sentinel (MIT). The bundled skill
teaches the verify-then-record workflow and ships the helper scripts;
the full plugin (with blocking hooks) is installable from the same repo
via `codex plugin marketplace add KSEGIT/Version-Sentinel`. Test cases
use public registries (npm, PyPI, crates.io, NuGet) and need no
credentials or special data.
