# Version Sentinel site

A framework-free static page served at `/Version-Sentinel/`. Production files
are only in `public/`; no runtime packages or third-party page requests are needed.
Development tools are exact versions in `package-lock.json`.

From this directory, with a current Node.js release and npm:

```sh
npm ci
npx playwright install chromium
npm run serve
```

Open http://127.0.0.1:4173/Version-Sentinel/. Paths outside that prefix return 404.
The server uses Node built-ins and serves only `public/` on loopback port 4173.

```sh
npm run test -- tests/content.spec.mjs
npm run check:html
```

Tests run Chromium at 375, 768, and 1440 pixels, each in light and dark mode.
They also open JavaScript-disabled contexts in each project. HTML and JSON test
reports, full-page screenshots, and test artifacts are written under ignored
`reports/`. The test command removes the inherited `NO_COLOR` variable so it
does not conflict with Playwright's `FORCE_COLOR` preference.

The complete-site commands below are reserved for the later quality-gate tools:

```sh
npm run check:links
npm run check:lighthouse
npm run profile:motion
```

The public files can be deployed without a build step. Package only `public/`,
including `.nojekyll`; exclude plans, tools, tests, reports, package manifests,
and `node_modules/`. The project-path `robots.txt` cannot control the owner-site
root. Repository settings and production deployment are separate approval steps.

See [ASSETS.md](ASSETS.md) for fixed upstream font sources, licenses, historical
example verification, and local image generation. Read the repository's
Version Sentinel instructions before changing tool dependencies.

The static page preserves the final example transcript and every installation
section without JavaScript. Interactive controls are hidden until an enhancement
provides their behavior. No scripts are needed for this static baseline.
