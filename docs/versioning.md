# Versioning

version-sentinel uses [Semantic Versioning](https://semver.org/) and [Conventional Commits](https://www.conventionalcommits.org/), driven by [release-please](https://github.com/googleapis/release-please) (`release-type: simple`).

## TL;DR

1. Write Conventional Commits on feature branches.
2. Open a PR, merge it into `main`.
3. `release-please` opens a **release PR** on `main`. Merging that release PR cuts the tag + GitHub Release.

Day-to-day: you do not edit `version.txt`, `.release-please-manifest.json`, `CHANGELOG.md`, or `.claude-plugin/plugin.json` `$.version` manually. release-please owns all four.

## Version bump rules

Computed from commits since the last release tag.

| Commit prefix                      | Bump    | Example                            |
| ---------------------------------- | ------- | ---------------------------------- |
| `feat:`                            | minor   | `feat: add go.mod parser`          |
| `fix:`                             | patch   | `fix: handle empty requirements`   |
| `feat!:` / `fix!:`                 | **major** | `feat!: rename /vs-record to /vsr` |
| Body contains `BREAKING CHANGE:`   | **major** | (any prefix)                       |
| `chore:` / `docs:` / `ci:` / `test:` / `refactor:` / `perf:` / `style:` | none — won't open a release PR on its own | `chore: bump checkout action`      |

If a release window contains both `fix:` and `feat:`, the highest applicable bump wins.

## The two-PR dance

### PR 1 — your work

- Branch off `main`, commit with Conventional prefixes, open PR.
- PR title itself matters if you **squash-merge** (title becomes the single commit). `feat: …` in the title = minor bump.
- On merge, the `release-please.yml` workflow runs on `main`.

### PR 2 — the release PR (auto-opened)

- Titled `chore(main): release <next-version>`.
- Changes:
  - `version.txt`
  - `.release-please-manifest.json`
  - `.claude-plugin/plugin.json` `$.version` (via `release-please-config.json` `extra-files`)
  - `CHANGELOG.md` — prepends a new `## [<version>] (<date>)` section built from commit messages since the last tag
- Keeps updating itself as new commits land on `main`; no need to close/reopen.

### Merging the release PR

- Creates tag `v<version>` (we set `"include-v-in-tag": true`).
- Publishes a GitHub Release with the generated CHANGELOG section as the body.
- Plugin users installing via the marketplace see the new `$.version` in `plugin.json` — triggers a refresh of the local plugin cache.

## Sources of truth

| What                                      | Updated by     |
| ----------------------------------------- | -------------- |
| `version.txt`                             | release-please |
| `.release-please-manifest.json`           | release-please |
| `.claude-plugin/plugin.json` `$.version`  | release-please |
| `CHANGELOG.md`                            | release-please |
| `.claude-plugin/marketplace.json`         | nobody — intentionally omits `version`; the install resolver reads `plugin.json`.|
| Git tags (`vX.Y.Z`)                       | release-please (on release-PR merge) |

If you hand-edit any file release-please owns, the next release-PR run will overwrite your change. Don't bother — use a commit message instead.

## CHANGELOG conventions

release-please generates sections grouped by commit type:

```
## [0.2.0] (2026-05-10)

### Features
- add go.mod parser (#42)

### Bug Fixes
- handle empty requirements (#47)
```

PRs are linked automatically via `(#42)` when the commit was merged through a PR.

A manually-maintained `[Unreleased]` block at the top of `CHANGELOG.md` is **not** read by release-please. It survives untouched and is safe for ad-hoc notes, but those notes won't appear in the generated release section unless you also land them as commit messages.

## Breaking changes

Two supported forms:

```
feat!: drop Python 3.10 support
```

or

```
feat: drop Python 3.10 support

BREAKING CHANGE: minimum Python is now 3.11 for tomllib.
```

Both trigger a major bump (`0.x.y` → `1.0.0`, or `1.x.y` → `2.0.0`).

While on `0.x.y`, a major-coded commit is technically treated as a minor bump by semver (the public API is "unstable"). release-please respects this: `feat!:` on `0.x.y` produces `0.(x+1).0`, not `1.0.0`. To cut `1.0.0`, land an explicit release by following the [pre-1.0 graduation](https://github.com/googleapis/release-please#how-do-i-publish-a-major-release) flow.

## Pre-releases

Not wired up yet. If needed, configure `release-please-config.json` with a `prerelease: true` + `prerelease-type: "beta"` on the relevant package. Pre-release tags look like `v0.3.0-beta.1`.

## CI integration

- `release-please.yml` — runs on `push` to `main`. Uses `${{ github.token }}` (the default `GITHUB_TOKEN`).
  - Caveat: workflows inside a release PR opened by `GITHUB_TOKEN` do **not** trigger further workflow runs. So tests won't auto-run on the release PR. Push an empty commit or re-run manually if you want them.
  - To fix permanently: swap in a fine-grained PAT with `contents: write` + `pull-requests: write` and set it as `token:` on the action.
- `changelog-check.yml` — fails PRs that bump version (`.claude-plugin/plugin.json` or `version.txt` changed) without also touching `CHANGELOG.md`. Skips release-please's own branches (prefix `release-please--`).
- `tests.yml` — runs on every PR across ubuntu/macos/windows. Must be green before any merge to `main`.

## Rolling back a bad release

1. Delete the tag on GitHub (`gh release delete v0.2.0 --yes --cleanup-tag`).
2. Land a `fix:` commit that reverts the breakage.
3. release-please opens a new release PR with the next patch version.

Do **not** hand-edit `.release-please-manifest.json` to roll it back — the tag resolution comes from git tags, not the manifest file.

## See also

- [CONTRIBUTING.md](../CONTRIBUTING.md) — how to write commits + run tests.
- [release-please docs](https://github.com/googleapis/release-please) — underlying behaviour.
- [Conventional Commits spec](https://www.conventionalcommits.org/en/v1.0.0/).
