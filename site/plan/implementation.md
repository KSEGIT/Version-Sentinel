# Version Sentinel Website Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build and validate the Version Sentinel landing page, open a green PR with reports and screenshots, and deploy it through GitHub Pages after approved settings and merge.

**Architecture:** Serve plain HTML, CSS, and browser JavaScript from `site/public/`. The page contains its final readable content before scripts run; scripts add theme selection, tabs, clipboard controls, and the terminal demonstration. Node tools serve the project base path and run development-only validation without changing plugin code.

**Tech Stack:** Semantic HTML, native CSS, ES modules, self-hosted IBM Plex fonts, Node built-ins, Playwright Test, axe-core, Lighthouse CI, HTML-validate, GitHub Actions.

**Spec:** [design.md](design.md). Design approved in chat; user resumed after the written spec handoff. Fresh builder review: nothing important left.

### Live tooling check, 2026-10-19

The npm registry returned these stable versions during read-only preparation:

| Development tool | Version | Declared Node requirement | Consulted upstream URL |
| --- | --- | --- | --- |
| `@playwright/test` | `1.64.1` | `>=20` | <https://registry.npmjs.org/@playwright%2ftest/latest> |
| `@axe-core/playwright` | `4.14.0` | `>=22.12.0` | <https://registry.npmjs.org/@axe-core%2fplaywright/latest> |
| `@lhci/cli` | `0.15.1` | none declared | <https://registry.npmjs.org/@lhci%2fcli/latest> |
| `html-validate` | `11.16.4` | `^22.22.0 || >=24.8.0` | <https://registry.npmjs.org/html-validate/latest> |

Use a Node 24 release >=24.8.0 in CI so all declared engine requirements are met.
This is planning evidence, not a Version Sentinel record or authorization to
install. Refresh the registry checks if stale, record the intended exact versions
with Version Sentinel, then add the manifest during Task 1 after plan approval.

## Global Constraints

- Production target: `https://ksegit.github.io/Version-Sentinel/`; base path `/Version-Sentinel/`.
- Worktree: `.worktrees/feat/website`, branch `feat/website`; never push or merge directly to `main`.
- All website source, tools, tests, assets, and reports live in `site/`; workflow files live in `.github/workflows/`.
- No changes to plugin code, manifests, hooks, root scripts, or release metadata.
- No framework, animation library, analytics, or third-party page requests.
- Register every npm dependency with a consulted live registry URL before adding/installing an exact version. Never use `VS_DISABLE`.
- Read Context7/current official API documentation before using a library. Relevant planning lookups are linked below; refresh as needed for the installed release.
- Use the palette and IBM Plex font roles from the spec; no purple/violet, gradient washes, neon glow, glassmorphism, or decorative blobs.
- Animate only transform and opacity. Honor reduced motion, including a preference change during playback.
- All content and installation instructions remain readable with JavaScript off.
- Text contrast >=4.5:1; WCAG 2.2 AA keyboard, focus, target size, and semantics.
- Mobile Lighthouse performance, accessibility, best practices, and SEO each >=95; measured CLS = 0.
- Axe: zero serious/critical issues; fix findings instead of suppressing them.
- Require screenshots at widths 375, 768, and 1440 in both themes.
- Ask before repository settings changes. README/homepage changes follow a verified production deployment.

## Review Focus

1. Project-path hosting: root-relative assets or hidden missing anchors must fail link tests, not silently work only at `/` (Tasks 1 and 4).
2. Storage and clipboard denial: the page still loads, commands remain selectable, and feedback describes the failed copy (Task 2).
3. Rapid replay, pause, and reduced-motion changes: cancel prior work and preserve the final terminal dimensions (Task 3).
4. JavaScript off, unsupported scroll timelines, and keyboard/touch use: no important text or registry information depends on animation or hover (Tasks 1–3).
5. CI/deployment boundary: tests, plans, package files, and reports never enter the public artifact; unapproved settings are never enabled by a workflow (Task 4).

## File map and shared interfaces

| Path | Responsibility |
| --- | --- |
| `site/public/index.html` | Content, SEO metadata, semantic diagram/diff, installation panels, final demo transcript |
| `site/public/styles.css` | Responsive layout, light/dark tokens, focus/contrast, transform/opacity motion and reduced-motion fallbacks |
| `site/public/theme-init.js` | Small synchronous first-paint theme initialization with guarded storage |
| `site/public/main.js` | Theme toggle, copy controls, install tabs; imports terminal initializer |
| `site/public/terminal.js` | Cancellable typing/play/pause/replay, motion-preference listener |
| `site/public/assets/` | Local fonts/licenses, logo derivative, social PNG, favicon files |
| `site/public/robots.txt`, `sitemap.xml`, `.nojekyll` | Search/distribution files |
| `site/tools/serve.mjs` | Node built-in static server, exact `/Version-Sentinel/` prefix, MIME types, 404s |
| `site/tools/check-links.mjs` | Local asset/anchor checks and bounded external URL checks |
| `site/tools/profile-motion.mjs` | Chromium CPU-throttled motion/CLS trace and readable results |
| `site/playwright.config.mjs`, `site/tests/*.spec.mjs` | Browser acceptance checks and report/screenshot attachments |
| `site/lighthouserc.cjs`, `site/.htmlvalidate.json` | Explicit quality thresholds and HTML rules |
| `site/package.json`, `site/package-lock.json` | Exact development-only tools and repeatable commands |
| `site/ASSETS.md`, `site/README.md` | Font/image provenance and local validation instructions |
| `site/reports/` | Ignored generated test evidence; uploaded as CI artifacts |
| `.github/workflows/site.yml`, `pages.yml` | PR checks and guarded production deployment |

DOM contract: anchors are exactly `top`, `problem`, `how-it-works`, `before-after`, `ecosystems`, `agents`, `comparison`, `install`. Theme button: `#theme-toggle`. Shared polite copy status: `#copy-status`. Each copy button has `data-copy-target` naming its visible code element ID. Install selectors are links to panel IDs until enhanced to tabs. Terminal root: `#terminal-demo`; buttons: `#demo-pause`, `#demo-replay`; final line: `#demo-result`; state attribute: `data-state="playing|paused|complete"`. Page scripts expose no global test-only functions.

CLI contract (all from `site/`): `npm run serve` serves `http://127.0.0.1:4173/Version-Sentinel/`; `npm run test` runs browser acceptance tests; `npm run check:html` validates public HTML; `npm run check:links` checks links; `npm run check:lighthouse` runs mobile LHCI; `npm run profile:motion` captures the throttled trace. Generated evidence goes under `site/reports/`.

## Task 1: Readable static page, assets, and browser test harness

**Owner:** fresh frontend implementer. **Files:** public HTML/CSS/assets/SEO, server, package files, Playwright configuration, `tests/content.spec.mjs`, `ASSETS.md`, `README.md`, root `.gitignore`.

**Consumes:** spec content, exact repository install instructions and palette. **Produces:** the DOM/CLI contract above, without interactive enhancement.

- [ ] Verify latest stable releases of `@playwright/test`, `@axe-core/playwright`, `@lhci/cli`, and `html-validate` from npm after web search. Record each using `bash ../scripts/vs-record.sh npm PACKAGE EXACT_VERSION CONSULTED_URL` from `site/`; then create the development manifest and lockfile. Use no production dependencies. Record the lookup commands/output in the verification notes.
- [ ] Add the server and Playwright configuration with six Chromium projects: widths 375, 768, 1440 paired with light/dark schemes. Use the project-prefixed base URL and a single server on port 4173. Configure HTML and JSON reports under `reports/`.
- [ ] Write and run failing content tests before creating the page. Include these assertions:

```js
await page.goto('/Version-Sentinel/');
await expect(page.getByRole('heading', { level: 1 })).toHaveText(
  'Check dependency versions before your agent writes them.'
);
for (const id of ['problem', 'how-it-works', 'before-after', 'ecosystems', 'agents', 'comparison', 'install']) {
  await expect(page.locator(`#${id}`)).toHaveCount(1);
}
expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true);
```

The initial run must fail because the page is absent; retain that result. Add tests for page/console errors, local resources returning success, all fragment links resolving, footer URLs, metadata, and no duplicate IDs. In a `javaScriptEnabled:false` context, assert all six installation sections and the final allowed terminal result are visible/readable in both color schemes.
- [ ] Implement the static page and responsive design. Use the documented lodash version `4.17.21` as a labeled historical example. For the hallucinated diff, first verify a chosen fictitious version is absent from the npm version list and label it illustrative; do not call the historical version current latest. Include exact commands and agent limitations from the spec. Keep registry information accessible to touch/keyboard, not only hover.
- [ ] Obtain local WOFF2 font files and OFL license from verified upstream IBM Plex sources; document URLs, upstream revision/version, and local names in `ASSETS.md`. Use only required Latin weights. Create favicon/logo assets from the existing repository vector; do not modify `assets/` at the root. Produce the 1200x630 social PNG from a code-native layout, with dimensions declared in metadata.
- [ ] Implement the SVG tool-call → hook → checks.json → allow/block diagram with accessible title/description, before/after diff, comparison table, prerequisites, legal footer links, sitemap and robots file. Preserve all final states without JavaScript.
- [ ] Run `npm run test -- tests/content.spec.mjs`, inspect 375px/1440px screenshots through Playwright MCP, and fix content/layout failures. Check each text color pair numerically. Commit this independently readable page once tests pass.

## Task 2: Theme, clipboard, and installation tabs

**Owner:** fresh browser-interaction implementer. **Files:** `theme-init.js`, `main.js`, relevant HTML/CSS, `tests/interactions.spec.mjs`. **Consumes:** Task 1 DOM. **Produces:** enhanced controls without losing no-JavaScript behavior.

- [ ] Write failing tests for default system theme, persisted explicit theme, reload, storage denied, exact copied command text, denied clipboard, and tab keyboard behavior. Assertions include:

```js
await page.getByRole('button', { name: /switch to dark theme/i }).click();
await expect(page.locator('html')).toHaveAttribute('data-theme', 'dark');
await page.reload();
await expect(page.locator('html')).toHaveAttribute('data-theme', 'dark');
await page.locator('[role="tab"]').first().focus();
await page.keyboard.press('End');
await expect(page.locator('[role="tab"]').last()).toBeFocused();
```

Grant clipboard permission for the success test and inspect `navigator.clipboard.readText()`. For failure, stub `writeText` to reject and require actionable copy-status text while code remains visible. Stub storage to throw before navigation and require the page/control to work.
- [ ] Run tests and retain failures. Implement `initCopyControls(root:Document):void`, `initInstallTabs(root:Document):void`, and `initThemeToggle(root:Document):void` in `main.js`; call them once on module load. Keep first-paint theme handling in `theme-init.js` with guarded storage. Use feature-detected `document.startViewTransition()` for opacity-only theme changes; bypass under reduced motion.
- [ ] Enhance install links to standard ARIA tabs only after event handlers are ready. Support click, arrow keys, Home/End, proper selected/tabindex state, panel associations, and links from agent entries to their correct install panel. Keep no-JavaScript instruction sections intact.
- [ ] Run interaction/content tests in both themes. Verify keyboard focus visibility and non-obscured targets through Playwright MCP. Commit after the fresh task review passes.

## Task 3: Terminal demonstration and explanatory scroll motion

**Owner:** fresh motion implementer. **Files:** `terminal.js`, relevant HTML/CSS/main import, `tests/motion.spec.mjs`, `tools/profile-motion.mjs`. **Consumes:** Task 1 demo/diagram markup. **Produces:** `initTerminalDemo(root:Document):void` export and accessible playback controls.

- [ ] Write failing tests for the automatic sequence, displayed exit 2, lookup/record/exact retry ordering, pause/resume, complete state, replay, rapid replay, and reduced motion before and during playback. Require final content immediately under reduced motion:

```js
await page.emulateMedia({ reducedMotion: 'reduce' });
await page.goto('/Version-Sentinel/');
await expect(page.locator('#terminal-demo')).toHaveAttribute('data-state', 'complete');
await expect(page.locator('#demo-result')).toBeVisible();
```

Measure terminal bounds before/after playback/replay and record layout-shift entries. Assert no overlap after rapid replay, no page errors, and a pause button that actually stops visible typing until resumed.
- [ ] Retain failing results; implement one cancellable demo controller. Use a single timer chain or abortable sequence, cancel it before replay, and finish immediately when reduced motion is requested. Keep static transcript available to assistive technology without announcing individual characters. Reserve its layout from first paint.
- [ ] Add SVG connector scale reveals and active-step opacity overlays with `animation-timeline:view()`, staggered grid transform/opacity entrances, and `scaleX` scroll progress. Use `@supports` so unsupported browsers keep static content. Reduced-motion rules must restore all final states; no JS animation loop on scroll.
- [ ] Run motion tests and manually inspect diagram/grid behavior, focus/touch registry details, and no-JavaScript rendering with Playwright MCP. Capture a Chromium trace with 4x CPU throttling at 375px, including frame timing, long tasks, and layout-shift evidence. Describe the emulation limit; a lab profile is not proof from a physical phone. Fix sustained missed-frame work within the page before proceeding.
- [ ] Run all existing site acceptance tests and commit once the fresh task reviewer passes.

## Task 4: Accessibility/performance gates and GitHub Pages workflows

**Owner:** fresh QA/CI implementer. **Files:** accessibility tests, validators/link tool, LHCI configuration, both workflows, site README. **Consumes:** final public files and package tools. **Produces:** repeatable quality commands, six screenshots, axe/Lighthouse reports, minimal public artifact.

- [ ] Add axe tests in light/dark and each install tab state. Save JSON reports and assert no violations with serious/critical impact; inspect and fix all actionable lower-impact findings too. Add manual keyboard/target/focus checklist results. Do not disable axe rules or exclude product sections to get a pass.
- [ ] Configure HTML-validate recommended rules and a link checker that resolves document IDs, local CSS/JS/font/image URLs and base paths. Check external URLs with bounded requests and actionable failure output; do not silently swallow failures. Run `npm run check:html` and `npm run check:links`; successful output must state validated document/link totals and zero failures.
- [ ] Configure LHCI for three mobile runs, four explicit category `minScore:0.95` error assertions, and `cumulative-layout-shift` maximum numeric value 0. Upload HTML/JSON to `reports/lighthouse/` using filesystem output. Use the project URL, not a different root-only version. Fix root causes if a gate fails; keep thresholds unchanged.
- [ ] Capture full-page screenshots after fonts load at 375, 768, 1440 in both themes. Ensure scroll-revealed content is visible in the delivered image while separately testing normal scrolling. Attach files to the Playwright report and retain exact filenames in verification notes.
- [ ] Recheck official latest action releases and pin full SHAs. `site.yml` runs on PRs touching `site/**`, either site workflow, or `.gitignore`; it installs exact locked tools, runs HTML/link/browser/axe/LHCI gates, and uploads reports with `if:always()`. Use `contents:read` and no production secrets on PRs.
- [ ] `pages.yml` runs on push to `main` for `site/**` and itself, plus `workflow_dispatch`. Validate first, then configure Pages with auto-enable disabled, upload only `site/public/`, and deploy through the `github-pages` environment using `pages:write`, `id-token:write`, concurrency control, and the verified official configure/upload/deploy actions. Guard manual deployment to `main`; never publish a feature branch through manual dispatch.
- [ ] Run `actionlint .github/workflows/site.yml .github/workflows/pages.yml`, all site quality commands, and `bash tests/run.sh`. Run `bash ../scripts/check-versions.sh` from `site/`; keep actual report output and explain any intentional pins. Confirm `git diff --name-only` contains only the permitted scope. Commit after fresh task review.

## Task 5: Whole-change review, PR evidence, deployment handoff

**Owner:** controller with fresh whole-branch reviewer and CodeRabbit review.

- [ ] Use the CodeRabbit code-review skill and fresh reviewer against the full branch diff, original user requirements, spec, and actual rendered evidence. Resolve material findings; rerun affected checks once code changes. Report any unavailable review tool honestly rather than substituting a claimed result.
- [ ] Create `site/plan/verification.md` with exact commands/output, dependency audit, Lighthouse scores/CLS, axe counts, manual accessibility observations, motion profile limits, and evidence paths. Mark production deployment and post-deploy README/homepage steps pending until actually verified.
- [ ] Commit/push `feat/website` and open a PR using a body file. Include summary, screenshots as actual previews or repository-hosted image links, Lighthouse/axe summaries, commands/output, and downloadable artifact links. Wait for CI and fix failures on the same branch; no force push or threshold weakening.
- [ ] Once the PR is concrete and green, ask the user to approve the exact Pages source setting command. Inspect current settings first; use POST only if Pages is absent, otherwise PATCH/PUT according to current GitHub API documentation. Never let configure-pages enable Pages without approval. The proposed setting is `build_type:"workflow"`; show the exact command at that point.
- [ ] Keep merge authorization separate from Settings approval. Do not merge directly to the default branch; the maintainer merges the PR unless explicitly authorizing an appropriate PR merge action. Observe that PR's merge and workflow by their real IDs; do not dispatch a production workflow manually.
- [ ] Verify the main-branch Pages deployment succeeds, the exact public URL returns 200, and live internal paths/assets work. Send the six screenshots. Then get approval for the exact repository homepage setting update and add the README website link in a follow-up worktree/PR if needed.
- [ ] Remove the original worktree only after all changes are committed/pushed and no process needs it. Preserve reports outside it or in CI artifacts first. Mark the goal complete only after the full user acceptance list is proven, including successful production deployment and post-deploy links/settings.

## Current API references checked while planning

- [Playwright configuration/emulation](https://playwright.dev/docs/test-use-options) and [axe testing](https://playwright.dev/docs/accessibility-testing), also queried through Context7 `/microsoft/playwright`.
- [Lighthouse CI configuration](https://github.com/GoogleChrome/lighthouse-ci/blob/main/docs/configuration.md), queried through Context7 `/googlechrome/lighthouse-ci`.
- [HTML-validate CLI](https://html-validate.org/usage/cli.html); Context7 did not return this library, so use its official docs.
- [IBM Plex upstream](https://github.com/IBM/plex) for local font provenance and license.

## Design research used by the plan

1. [IBM developer typography](https://www.ibm.com/brand/experience-guides/developer/brand/typography/): distinct prose/code roles and consistent hierarchy (Tasks 1–2).
2. [web.dev font performance](https://web.dev/learn/performance/optimize-web-fonts): limited local fonts and no late layout shifts (Tasks 1 and 4).
3. [MDN scroll-driven animations](https://developer.mozilla.org/en-US/docs/Web/CSS/Guides/Scroll-driven_animations): native view/scroll timelines with readable fallbacks (Task 3).
4. [MDN View Transitions](https://developer.mozilla.org/en-US/docs/Web/API/View_Transition_API/Using): feature-detected opacity transitions for theme changes (Task 2).
5. [WCAG 2.2](https://www.w3.org/TR/WCAG22/): contrast, keyboard operation, focus, and target requirements (Tasks 1–4).
