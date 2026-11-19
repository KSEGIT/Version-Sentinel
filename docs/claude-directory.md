# Claude directory package

The main repository contains runtime code, tests, website screenshots, and
development files. Submitting its root makes the directory inspect all of them.
The Claude directory uses a generated package on the `claude-directory` branch
instead. The source files remain on `main`.

## Build and publish

Build a package into a new directory:

```bash
bash tools/build-claude-plugin.sh /absolute/path/to/new-package
```

The builder refuses an existing destination. It copies an explicit set of
runtime files, the Claude manifest, hooks, commands, agents, the skill, license,
privacy policy, enforcement guide, and the Claude package README.

After this change is merged, the **Publish Claude directory package** workflow
builds the current `main` and publishes it to `claude-directory`. It runs for
pushes to `main`, published releases, and manual runs on `main`.

Release Please also calls this workflow directly when its root component
`release_created` output is `true`. This covers releases made with the default
`GITHUB_TOKEN`: GitHub does not start another release-event workflow for events
that token creates. With a personal access token, both paths can run; publishing
is serialized, and an identical package is a no-op. Each run checks out current
`main` when it starts so a queued release event does not republish an old tag.

The workflow's `contents: write` permission is needed to push the package branch.
It uses ordinary commits and a normal push, with no force push, and does not
change the source branch or the existing marketplace configuration.

The helper can also publish an already reviewed package from a source checkout:

```bash
bash tools/publish-claude-plugin.sh /absolute/path/to/new-package
```

It accepts a configured remote name as an optional second argument; the target
branch is always `claude-directory`. An identical package makes no new commit.
If the remote changes during publication, the normal push fails safely. Check
the branch and rerun after reviewing the change.

## Point the portal at the package

Once the workflow has created the branch:

1. Open Version Sentinel in the Claude directory developer portal.
2. Select **Settings**, then **Source**.
3. Keep the fixed repository `KSEGIT/Version-Sentinel` and repository-root plugin
   path. Changing either requires a new submission.
4. Set **Tracked branch or tag** to `claude-directory` and select **Save**.
5. Saving scans the branch's latest new commit as a new version. Inspect the
   **Review** tab before requesting publication. The live version stays in
   place, but saving the source cancels any pending publish request.

Changing the repository does not change the portal's existing source selection.
The package must be published and selected there before it affects review.
People using the existing custom marketplace can continue to use it.

## Review findings

| Finding | Package change or remaining action |
| --- | --- |
| Image or font file could run | Website assets, website workflows, and test files are excluded. Runtime source stays readable. |
| Download-and-run commands | Website screenshots that contain those examples are excluded. |
| Root `CLAUDE.md` is not loaded | The package has no root `CLAUDE.md`; the workflow instructions ship in `skills/version-sentinel/SKILL.md`. |
| README registry redirect | The package has a short Claude README without installation snippets or images. |
| Credential forwarding | The flagged runtime files do not explicitly read or forward account credentials. Public registry requests ignore the user's curl configuration. The privacy policy states what requests send. A reviewer must confirm any remaining warning. |
| Uses hooks | Accurate and retained: hooks provide advisory dependency diagnostics. |
| Images passed without a code check | No images or fonts are included in the package. |

Packaging does not grant Verified organization status. The directory may still
refuse the required hooks and scripts under its Verified organization rules.
Describe warning-only hooks accurately; do not disguise source files to bypass directory rules.
Local checks prove package contents and behavior; only portal validation can
confirm which directory findings have cleared.
