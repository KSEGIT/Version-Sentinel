# Version Sentinel site

A static page at `/Version-Sentinel/`. Only `public/` is deployed. It uses local
assets and has no runtime dependencies or third-party page requests.

Use Node.js 24 and npm from this directory:

```sh
npm ci
npx --no-install playwright install --with-deps chromium
npm run serve
```

Open http://127.0.0.1:4173/Version-Sentinel/. The loopback server rejects paths
outside that prefix. `PORT` selects another port; Lighthouse owns port 4174.

Run the same quality gates as CI:

```sh
npm audit
npm run test:tools
npm run check:html
npm run check:links
npm test
npm run check:lighthouse
npm run profile:motion
bash ../scripts/check-versions.sh
```

HTML validation uses the recommended rules and reports document and failure
counts. The link checker validates document IDs, local assets, CSS URLs, script
imports, SEO URLs, and the project base path. The known production origin/base
maps to `public/` until deployment; this does not prove production is live.
External URLs use four workers, two attempts, and a 12-second request timeout.
Any HTTP or network failure fails the command with its source file and URL.

Chromium tests run at 375, 768, and 1440 pixels in both themes. They cover normal
scrolling, keyboard controls, theme storage, copy feedback, motion preferences,
JavaScript-off content, overflow, and all six install tabs. Axe scans the full
page with every tab selected and all registry disclosures closed and open in
all six viewport/theme combinations (72 scans), plus six normal-motion scans.
Every violation fails, including
lower-impact findings. Automated checks do not prove complete WCAG conformance.

Six final full-page screenshots wait for fonts, the final transcript, and normal
scroll traversal. Capture then uses the documented reduced-motion final state
so scroll-driven sections stay visible in the full-page image. Each PNG is
attached to the Playwright report. The small reviewed subset is committed under
`review/screenshots/`; full evidence stays in ignored `reports/`.

Lighthouse CI performs three mobile runs on the real project path. Every run
must score at least 0.95 for performance, accessibility, best practices, and SEO,
with CLS exactly zero. JSON and HTML output goes to `reports/lighthouse/`.
The dependency overrides keep LHCI 0.15.1 with Lighthouse 13.5.0 and patched tmp,
basic-ftp, and uuid. uuid 11.1.1 is a deliberate CommonJS compatibility pin.
Before changing these, consult upstream metadata, record exact versions with
Version Sentinel, run full `npm audit` (including development dependencies), and
prove LHCI collect/assert/report still works. `check-versions.sh` does not inspect
npm overrides; check their dependency tree separately with:

```sh
npm ls lighthouse puppeteer-core @puppeteer/browsers extract-zip tmp basic-ftp uuid
```

CI retains `reports/` for 14 days even when a quality step fails. Pages runs only
on main, validates first, and uploads only `public/`, including `.nojekyll`.
Tests, plans, tools, package files, node_modules, reports, and review screenshots
are outside the Pages artifact. Pages auto-enable is disabled. Repository
settings and first production deployment require separate approval. The
project-path `robots.txt` cannot control the owner-site root.

See [ASSETS.md](ASSETS.md) for asset licenses and provenance. Without JavaScript,
the final transcript, all install instructions, and native registry disclosures
remain available.
