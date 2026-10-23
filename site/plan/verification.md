# Website verification

Recorded 23 October 2026 for [PR #37](https://github.com/KSEGIT/Version-Sentinel/pull/37).
The site is static HTML, CSS, and browser JavaScript in `site/public/`. It has no
production package dependencies or framework build step. Only that directory is
published; tests, plans, reports, and review screenshots stay outside Pages.

## Final local checks

Commands run from `site/` unless marked as repository-root commands. Raw logs,
JSON, HTML reports, screenshots, and traces are retained in `site/reports/` during
development. CI uploads its reports; the [PR checks](https://github.com/KSEGIT/Version-Sentinel/pull/37/checks)
are authoritative for the committed branch head.

| Command | Observed result |
| --- | --- |
| `npm test` | 168 passed; 0 failed, skipped, or flaky |
| axe scans within the browser suite | 78 scans; 0 violations |
| `npm run test:tools` | 2 passed |
| `npm run check:html` | 1 HTML document; 0 failures |
| `npm run check:links` | 52 links, including 12 external URLs; 0 failures |
| `npm run check:lighthouse` | Three mobile Lighthouse 13.5.0 runs passed every threshold |
| `npm audit --json` | 0 vulnerabilities, including development dependencies |
| `bash ../scripts/check-versions.sh` | All four direct development tools current |
| root `bash tests/run.sh` | 30 groups; 0 failed |
| root `actionlint .github/workflows/site.yml .github/workflows/pages.yml` | Exit 0; no diagnostics |
| JavaScript syntax checks and `git diff --check` | Exit 0 |

The final fix wave changed only focus styling, local copy feedback, related tests,
the development profiler, and screenshots. Dependency and workflow files were
unchanged from the audited quality-gate commit.

## Mobile Lighthouse

The final fix reports were collected on the real project path with mobile
settings. All three JSON reports identify Lighthouse 13.5.0 and `formFactor:
mobile`. The filesystem reports include HTML and JSON.

| Run | Performance | Accessibility | Best practices | SEO | CLS |
| --- | ---: | ---: | ---: | ---: | ---: |
| 1 | 100 | 100 | 100 | 100 | 0 |
| 2 | 100 | 100 | 100 | 100 | 0 |
| 3 | 100 | 100 | 100 | 100 | 0 |

The four required category gates remain at least 95 for every run; the CLS gate
remains zero. No threshold was lowered. Local report filenames contain the
timestamps `16_57_08`, `16_57_18`, and `16_57_27` on 23 October 2026.

## Accessibility and behavior

Browser checks cover 375px, 768px, and 1440px in both themes, plus touch input,
320px reflow, 200% text size, keyboard focus, tab/history navigation, clipboard
success/denial/retry, paused and repeated demos, live reduced-motion changes,
JavaScript-off content, unsupported scroll animation, assets, and anchors.

The two final review findings have focused RED-to-GREEN regressions:

- The dark terminal now uses its own high-contrast focus color in both themes.
  The former light-theme outline was 2.087:1; tests require a visible outline
  with at least 3:1 non-text contrast.
- Every copy control now has nearby visible success or manual-copy guidance,
  while retaining one polite live region. Hero failure feedback was inspected
  inside the 375x900 viewport in both themes. Its space is reserved from first
  paint, including narrow and enlarged-text layouts.

The 78 axe scans cover both themes, all installation panels, open/closed registry
details, and normal motion. No rules or product sections were excluded. Remaining
`incomplete` results concern color-contrast inference for SVG overlap and clipped
horizontal table cells. Manual review checked the actual fills and text colors:
used text pairs are at least 5.30:1, table cells are readable by keyboard scrolling,
and no unsupported ARIA naming result remains. Automated scans and these manual
checks do not constitute certification across all assistive technologies.

## Motion evidence and limits

The final Chromium 156 profile used a 375x900 mobile/touch viewport and 4x CPU
slowdown. It recorded load, replay, copy success, copy denial, and scrolling.
CLS and the sum of all layout-shift values, including recent-input shifts, were
zero. Every phase had p95 callback intervals near 16.7ms.

The load sample included one 98ms long task and one 116.7ms frame interval. It
was isolated, with no consecutive run of missed intervals. Replay, both copy
paths, and scrolling had no long tasks or intervals above 25ms; their maximum
interval was 16.8ms. The outlier is retained rather than replaced by a better run.
The small [summary](../review/motion-summary.json) is committed; raw measurements
and trace are in the local final-fix report directory.

These are lab callback timings, not physical display presentation. A physical
mid-range phone, its GPU, heat, battery state, and competing processes were not
measured. The implementation uses native transform/opacity effects and small
JavaScript; the report does not promise an exact frame rate on every device.

## Version Sentinel report

The mandatory audit output was:

```text
ECOSYSTEM    PACKAGE                                  CURRENT         LATEST          STATUS
-----------------------------------------------------------------------------------------
npm          @axe-core/playwright                     4.14.0          4.14.0          ok
npm          @lhci/cli                                0.15.1          0.15.1          ok
npm          @playwright/test                         1.64.1          1.64.1          ok
npm          html-validate                            11.17.0         11.17.0         ok
```

Every direct tool was looked up on the live npm registry and recorded before
manifest changes. The parser does not inspect npm overrides, so their evidence
was checked separately:

| Override | Exact version | Reason and proof |
| --- | --- | --- |
| `lighthouse` | 13.5.0 | Current upstream; both LHCI consumers use it; real collect/assert/HTML output passes |
| `tmp` | 0.2.7 | Current patched upstream; both installed paths use it |
| `basic-ftp` | 6.2.3 | Current patched upstream; get-uri uses it |
| `uuid` | 11.1.1 | Recorded intentional CommonJS compatibility pin; the consulted version is patched |

The overrides were recorded before edits. Full tree inspection confirms the
unpatched `extract-zip` chain is absent. The clean audit includes all development
packages. These cross upstream ranges; actual tests establish this toolchain's
behavior, not a blanket upstream compatibility promise.

Known toolchain debt remains: upstream deprecation notices for inflight, rimraf,
glob, and OpenTelemetry, plus LHCI's optional GitHub-token warning during
filesystem output. These notices are retained; no dummy secret, warning filter,
audit omission, or disabled check was added.

## Screenshot previews

The six final full-page PNGs use the readable reduced-motion final state after
normal-scroll behavior has been tested. Fonts were ready before capture.

| Width | Light | Dark |
| --- | --- | --- |
| 375px | [PNG](../review/screenshots/final-375-light.png) | [PNG](../review/screenshots/final-375-dark.png) |
| 768px | [PNG](../review/screenshots/final-768-light.png) | [PNG](../review/screenshots/final-768-dark.png) |
| 1440px | [PNG](../review/screenshots/final-1440-light.png) | [PNG](../review/screenshots/final-1440-dark.png) |

## Delivery boundary

Native task reviews and a whole-branch review were run. The final review's two
Important findings are covered by the fix regressions above; independent scoped
re-review and actual CI must pass before readiness is claimed. The CodeRabbit CLI
browser login timed out without a review. The repository CodeRabbit app is present
but skips drafts; its eventual PR review must be inspected as a separate result.

No Pages setting or homepage value was changed during creation. Enabling Pages,
merging to main, confirming the main deployment and live HTTP 200, and the later
README/homepage updates remain separate delivery steps. The production target is
`https://ksegit.github.io/Version-Sentinel/`.
