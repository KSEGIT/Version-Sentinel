# Version Sentinel landing site design

Date: 2026-10-15

## Approved direction

Build one public, mobile-first landing page at
`https://ksegit.github.io/Version-Sentinel/`. The audience is developers using
coding agents. The primary task is to understand the verify-and-record workflow
and install the correct integration. The user approved the recommended static
HTML/CSS/minimal JavaScript option and the petrol/teal, IBM Plex design direction.

The alternative was Astro: static output and reusable components, but an extra
framework and build dependency for a single page. Use no framework or animation
library. Development-only tools may live in `site/package.json`.

## Scope and boundaries

- Keep site source, assets, tests, test configuration, and planning files in `site/`.
- Add `.github/workflows/pages.yml` and a separate PR site-validation workflow.
- Add `.worktrees/` and generated site output to the root `.gitignore`.
- Do not change plugin code, manifests, hooks, root scripts, or release metadata.
- Add a README website link only after the production deployment works.
- Ask before changing repository settings, including Pages source and homepage.
- Work on `feat/website` in `.worktrees/feat/website`; push and open a PR, never
  push or merge directly to `main`. Remove the worktree after its work is safely
  committed and pushed; continue any post-merge work in a fresh worktree and PR.

## Content contract

Facts come from `README.md`, `CLAUDE.md`, `AGENTS.md`, `CHANGELOG.md`, `docs/*.md`,
`PRIVACY.md`, `TERMS.md`, and `LICENSE`. The existing `assets/` provides the logo
shape and cyan brand cue. Do not copy stale version claims from hero artwork or
marketing drafts. Do not invent numbers, endorsements, or security guarantees.

Hero headline: **Check dependency versions before your agent writes them.**
Supporting copy explains the fresh, source-cited registry check required before
dependency additions, bumps, and downgrades. The hero install control copies both
Claude Code installation lines, with a link to other agents below.

The page contains these sections and stable anchors:

1. `#top`: value proposition, install command, copy control, terminal demo.
2. `#problem`: hallucinated versions, stale pins, silent downgrades; short text
   explains the requirement rather than promising a vulnerability scanner.
3. `#how-it-works`: tool call, hook, local check record, allow/block decision;
   blocked flow continues through WebSearch, `/vs-record`, and exact-version retry.
4. `#before-after`: side-by-side `package.json` diff; the guessed version is
   explicitly an illustrative nonexistent version and the verified version is a
   documented example, not a permanently current “latest” claim.
5. `#ecosystems`: npm, pip/PyPI, cargo/crates.io, NuGet; include supported manifest
   names and npm/pnpm/yarn/bun, pip/Poetry/uv manager coverage.
6. `#agents`: Claude Code, Kimi Code, GitHub Copilot in VS Code, Gemini CLI,
   OpenAI Codex, Zed; note the Claude-format z.ai integration without claiming
   live verification of ZCode. Label Zed advisory and Copilot hook availability
   according to the repository documentation.
7. `#comparison`: semantic comparison table. Version Sentinel checks before an
   agent edit/install, Dependabot and Renovate propose asynchronous update PRs,
   and generic dependency-audit skills scan after the fact and are advisory.
   These tools serve different stages; do not claim replacement or superiority.
8. `#install`: agent tabs, prerequisites, exact repository-documented commands,
   and required setup/trust notes. With JavaScript off, all agent instructions
   remain readable. The footer links GitHub, MIT license, changelog, privacy,
   and terms to the corresponding repository pages.

Exact installation content:

| Agent | Command or setup |
| --- | --- |
| Claude Code | `/plugin marketplace add https://github.com/KSEGIT/Version-Sentinel.git`, then `/plugin install version-sentinel@version-sentinel-marketplace` |
| Kimi Code | `/plugins install https://github.com/KSEGIT/Version-Sentinel` |
| Gemini CLI | `gemini extensions install https://github.com/KSEGIT/Version-Sentinel`, then `bash ~/.gemini/extensions/version-sentinel/platforms/gemini/setup.sh`; restart Gemini |
| Codex | `codex plugin marketplace add KSEGIT/Version-Sentinel`, then `codex plugin add version-sentinel`; complete `/hooks` trust review |
| Copilot in VS Code | Use this repository as workspace or copy its `.github/` and `.agents/skills/` adapters with required scripts; link the repository setup guidance rather than inventing an install command |
| Zed | Follow `docs/zed.md`: project `AGENTS.md`, `.agents/skills/`, and workflow scripts; no automatic hook blocking |

The terminal is a local illustration, not a live package installation. Use a
repository-documented example version and label it as an example. Show an edit,
`BLOCKED: version-sentinel` and exit 2, WebSearch against the npm package page,
`/vs-record npm lodash <example-version> https://www.npmjs.com/package/lodash`,
then a retry naming that exact version and an allowed result. A recent record
applies to its recorded version; do not imply an unpinned retry passes. The
default freshness window is 24 hours; intentional pins can carry a reason.

## Visual system

Use a measured engineering style with one large terminal as the main visual.
Keep surrounding sections quiet, left aligned, and based on their actual content
instead of repeating identical cards. No purple/violet, gradient washes, neon
glow, glassmorphism, or decorative blobs.

| Token | Light value | Dark value | Purpose |
| --- | --- | --- | --- |
| Page | `#F4F7F7` | `#142E32` | Main background |
| Ink | `#142E32` | `#EAF2F1` | Body and headings |
| Teal | `#006568` | `#7CDAD4` | Links, focus, positive state |
| Amber | `#9A4A00` | `#F5C484` | Check-required state |
| Cyan | `#03D8F8` | `#03D8F8` | Small brand accent, not light-theme body text |

Derive secondary surfaces and borders from these hues; measure every text and
control pairing. Use labels/icons as well as color for blocked and allowed states.
Use self-hosted IBM Plex Sans for headings and prose, IBM Plex Mono for code.
Include font licenses and provenance. Limit weights and use local WOFF2 assets
with a font loading strategy that prevents late layout shifts.

Desktop hero: text and install on the left, terminal on the right. On mobile,
show the heading, install, then terminal in reading order. Use a maximum content
width near 72rem, fluid gutters, body text at least 1rem, and prose below 80
characters per line. Tables and code may scroll within labeled containers;
the page itself must not overflow at 375px.

## Interaction and motion

- Honor `prefers-color-scheme` initially; a keyboard-accessible toggle stores the
  explicit choice locally. Apply it before first paint. Storage errors must not
  break the page. Use a short opacity-only View Transition when supported, with
  an immediate fallback and no animation under reduced motion.
- Terminal types the first edit, then reveals the block, lookup, record, and
  passing retry once. Reserve the final terminal size. Provide pause and replay
  controls; restarting cancels earlier timers so multiple runs cannot overlap.
  Do not announce individual typed characters to screen readers.
- SVG flow connectors reveal using transform scaling or transformed masks,
  rather than animating stroke properties. Highlight the current decision step
  with an opacity overlay. CSS scroll-driven animations are the first choice;
  unsupported browsers show a readable static diagram.
- Ecosystem/agent entries have short staggered opacity/transform reveals. Registry
  information is available on hover, keyboard focus, and touch, and remains
  discoverable without hover. Agents use the same four registries; none gets a
  fictional agent-specific registry.
- Copy controls announce success/failure through one polite status region. Failed
  clipboard access leaves the visible command available for manual copying.
- A thin scroll-linked progress indicator uses `scaleX` and is not a focusable
  control. No continuous JavaScript scroll animation loop.
- Animate only transform and opacity. No heavy motion library. Prefer CSS
  transitions, `animation-timeline`, and View Transitions; use small JavaScript
  for typing, replay/pause, tabs, clipboard, and theme state.
- Reduced-motion mode shows final readable demo/diagram/grid states immediately,
  including when the preference changes while the page is open. With JavaScript
  off, the final demo and all installation sections remain readable.

## Accessibility and performance acceptance

Target WCAG 2.2 AA: text contrast at least 4.5:1, sufficient non-text contrast,
semantic landmarks/headings, a skip link, descriptive links, visible focus,
keyboard navigation, focus not obscured, adequate touch targets, and accessible
SVG descriptions. Tabs use standard arrow/Home/End behavior and associate each
panel with its tab. No automatically moving content without a pause mechanism.

Require mobile Lighthouse scores >=95 in performance, accessibility, best
practices, and SEO. Require measured CLS = 0 for the tested page load and demo
interactions. Use only local page assets, set image dimensions, reserve animated
areas, and keep the production page independent of development dependencies.
Profile motion with mobile CPU throttling; record findings rather than treating
a desktop Lighthouse score as proof of 60 fps on a mid-range phone.

## SEO and deployment

Set title, description, canonical URL, Open Graph and Twitter metadata, a local
1200x630 social PNG, SVG favicon and suitable raster fallback, `sitemap.xml`,
`robots.txt`, and `.nojekyll`. All links/assets must work under the project base
path `/Version-Sentinel/`. A project-path `robots.txt` cannot control the owner
site root; do not imply otherwise.

Package only public HTML/CSS/JavaScript/assets/SEO files for Pages. Exclude
package manifests, tests, plans, reports, and node_modules from the artifact.
The deploy workflow uses the upstream-verified configure-pages v6,
upload-pages-artifact v5, and deploy-pages v5 majors, pinned to full commit SHAs.
Recheck releases before writing the workflow. Trigger on pushes to `main` for
`site/**` and the Pages workflow itself, plus `workflow_dispatch`. Use the
`github-pages` environment and least-privilege deployment permissions.

Do not let configure-pages silently enable Pages before user approval. Prepare
the exact `gh api` settings command and ask after the site and PR are reviewable.
After merge, confirm the Pages workflow succeeds and the target URL returns 200.
Then request approval for the repository homepage change and add the README link
through a follow-up PR if it could not truthfully be added to the initial PR.

## Verification and delivery evidence

- Playwright checks page load, console/page errors, internal links/assets/anchors,
  copy content and feedback, theme behavior/persistence, tabs/keyboard controls,
  demo playback/pause/replay, reduced motion, JavaScript-off content, and overflow.
- Capture 375px, 768px, and 1440px full-page screenshots in both themes.
- Run axe-core in both themes and relevant tab states; zero serious/critical
  issues. Do not treat a clean automated scan as complete WCAG proof.
- Run mobile Lighthouse CI with each of the four categories >=0.95. Keep JSON
  and HTML reports, screenshot assets, and CLS/performance evidence.
- Run HTML validation and link checks in CI on PRs touching `site/` and workflow
  files. Check local anchors/assets strictly; report external failures clearly.
- Verify each dependency on its live upstream registry, record with
  `scripts/vs-record.sh`, then add the exact version. Never use `VS_DISABLE`.
  Consult Context7/current official docs before using test libraries and APIs.
- Run `bash ../scripts/check-versions.sh` from `site/` at the end and include its
  output. Run existing `bash tests/run.sh` and relevant lint/workflow checks.
- Use the CodeRabbit code-review skill and a fresh whole-change review. Fix
  material findings, then rerun affected checks.
- Push branch, open PR, wait for green required CI, and include report summaries,
  command output, artifact links, and screenshot previews in the PR body. Keep
  the goal incomplete until production deploy and final URL verification pass.

## Current sources consulted for this design

1. [IBM developer typography](https://www.ibm.com/brand/experience-guides/developer/brand/typography/): distinct prose/code roles and a consistent type hierarchy.
2. [web.dev font performance](https://web.dev/learn/performance/optimize-web-fonts): font loading, resource size, and avoiding layout shifts.
3. [MDN CSS scroll-driven animations](https://developer.mozilla.org/en-US/docs/Web/CSS/Guides/Scroll-driven_animations): declarative scroll/view timelines with static fallbacks.
4. [MDN View Transitions](https://developer.mozilla.org/en-US/docs/Web/API/View_Transition_API/Using): feature-detected transitions for DOM state changes.
5. [WCAG 2.2](https://www.w3.org/TR/WCAG22/): contrast, keyboard access, target size, and focus requirements.

These sources were checked for current guidance during research; they are not
presented as claims that each practice originated in 2026.
