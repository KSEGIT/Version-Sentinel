# Distribution & Marketplace Status

Where Version Sentinel is listed and how it can be installed. Public sources
checked on **2026-11-23**. A repository install, an open submission, and a
published directory entry are separate states. Account-only portal status and
blocked pages remain unverified.

Project website: <https://ksegit.github.io/Version-Sentinel/>.

Submission status legend:

- **listed** — a current public catalog contains Version Sentinel
- **pending** — a public submission remains open; the catalog does not list it
- **rejected** — a submission was closed without publication
- **ready-in-repo** — repository integration files are available; this does not
  establish a public catalog listing or a tested install flow

## Matrix

| Platform | Install mechanism (verified) | Listing / marketplace | Submission status | Owner next action |
|----------|------------------------------|-----------------------|-------------------|-------------------|
| Claude Code | Self-hosted `.claude-plugin/marketplace.json`, or `/plugin marketplace add anthropics/claude-plugins-community` → `/plugin install version-sentinel@claude-community` | **Listed** in Anthropic community marketplace; absent from `claude-plugins-official` | **listed** | Update the existing community listing through the developer portal; its description and homepage still reflect an older release |
| z.ai (GLM Coding Plan / ZCode) | Repository install through the Claude Code plugin format | Not in the current `zai-org/zai-coding-plugins` catalog | **pending** | Track [PR #23](https://github.com/zai-org/zai-coding-plugins/pull/23), still open on 2026-11-23 |
| Kimi Code | Direct GitHub install or the self-hosted `kimi-marketplace.json` catalog | Self-hosted catalog; listing in Kimi's default catalog not verified | **ready-in-repo** | Verify installed details after an update; see `docs/e2e-checklist.md` for untested flows |
| Gemini CLI | `gemini extensions install https://github.com/KSEGIT/Version-Sentinel`, then run `platforms/gemini/setup.sh` in the installed extension | [Official extensions gallery](https://geminicli.com/extensions/) lists `@KSEGIT/Version-Sentinel` | **listed** | Gallery currently shows stale v0.4.5 metadata; monitor crawler refresh |
| OpenAI Codex | Self-hosted GitHub marketplace using `.codex-plugin/plugin.json` | Self-hosted install confirmed; official public directory listing not verified | **ready-in-repo** | Update the installed plugin to pick up `interface.websiteURL`; hooks cannot ship through the public directory |
| GitHub Copilot CLI | Root `plugin.json` passed the submission's install smoke test | Absent from [awesome-copilot external catalog](https://github.com/github/awesome-copilot/blob/main/plugins/external.json) | **rejected** | Submission [#2598](https://github.com/github/awesome-copilot/issues/2598) closed 2026-08-11; no marketplace install claim |
| GitHub Copilot in VS Code | Repo files under `.github/` and `.agents/skills/` | No Version Sentinel marketplace listing verified | **ready-in-repo** | Use the repository integration |
| Zed | Repo instructions and skills; see `docs/zed.md` for limits | Absent from the [Zed extensions catalog](https://github.com/zed-industries/extensions/blob/main/extensions.toml) | **ready-in-repo** | Use the repository integration |

## Per-platform details and sources

### Claude Code — Anthropic community marketplace

- **Confirmed listed:** the current
  [community catalog](https://github.com/anthropics/claude-plugins-community/blob/main/.claude-plugin/marketplace.json)
  contains `version-sentinel` with source `KSEGIT/Version-Sentinel`, pinned to
  commit `df2dde790963b161fea28ea1f2307bbb8fec7b47`.
  The marketplace name is `claude-community`.
- The entry's homepage is still the GitHub README and its description still
  claims hard blocking. Both need an update to the current advisory behavior
  and <https://ksegit.github.io/Version-Sentinel/>. Changing this repository's
  manifests alone does not change that separately maintained catalog entry.
- The [community marketplace README](https://github.com/anthropics/claude-plugins-community)
  identifies it as a read-only mirror, synced nightly from Anthropic's review
  pipeline. Submit updates through the developer portal, not a direct PR.
- No Version Sentinel entry was found in the current
  [official marketplace catalog](https://github.com/anthropics/claude-plugins-official/blob/main/.claude-plugin/marketplace.json).
  This is a separate catalog from the community marketplace.
- Current [publishing documentation](https://code.claude.com/docs/en/plugins/publish)
  directs authors to <https://claude.ai/directory/manage>. The current account's
  submission and update status was not inspected.
- The [marketplace reference](https://code.claude.com/docs/en/plugins/marketplace-reference)
  supports `homepage` in plugin entries and `plugin.json`. Entry display fields
  override manifest values; before installing a remote-source plugin, only
  the entry's fields are available.

### z.ai (GLM Coding Plan / ZCode)

- The current [z.ai catalog](https://github.com/zai-org/zai-coding-plugins/blob/main/.claude-plugin/marketplace.json)
  lists `glm-plan-usage` and `glm-plan-bug`, but not Version Sentinel.
- Submission [PR #23](https://github.com/zai-org/zai-coding-plugins/pull/23)
  remains **open**, with no merge date, as checked through GitHub on
  2026-11-23. This is a pending submission, not a published listing.
- Repository installation through the Claude Code format remains separate
  from z.ai catalog publication. The ZCode hook-loading path has not been
  tested here; see [Z.ai tool integration docs](https://docs.z.ai/devpack/tool/others).

### Kimi Code

- Direct GitHub installation and the self-hosted `kimi-marketplace.json`
  catalog are available. A Version Sentinel entry in Kimi's default
  Official/Curated catalog was not verified on **2026-11-23**.
- Kimi now has Official and Curated marketplace tabs. The old statement that
  no Kimi marketplace exists is outdated.
- The manifest supports `homepage` and `interface.websiteURL`. Both should
  use [the project website](https://ksegit.github.io/Version-Sentinel/).
  Marketplace API entries also support `homepage`.
- Sources: [Kimi plugins and manifest reference](https://moonshotai.github.io/kimi-code/en/customization/plugins.html),
  [marketplace API reference](https://moonshotai.github.io/kimi-code/en/reference/server-api.html).

### Gemini CLI — extensions gallery

- **Listed**, checked **2026-11-23**: the
  [official gallery](https://geminicli.com/extensions/) contains
  `version-sentinel`, publisher `@KSEGIT/Version-Sentinel`, with a direct
  GitHub install command. It currently shows **0.4.5** and an old description
  that says dependency edits are blocked. Current repository behavior is
  advisory; the gallery copy is stale.
- GitHub already has the `gemini-cli-extension` topic and the correct
  [website URL](https://github.com/KSEGIT/Version-Sentinel). No topic change
  or submission form is needed. The gallery crawls tagged public repositories.
- The [manifest reference](https://geminicli.com/docs/extensions/reference/)
  documents no `homepage` or website field. Keep the website in GitHub's About
  metadata and the README rather than add an unsupported manifest key.
- After installation, activate hooks with
  `bash ~/.gemini/extensions/version-sentinel/platforms/gemini/setup.sh`;
  see `docs/e2e-checklist.md` for the hook schema limits.
- Source: [Release extensions](https://geminicli.com/docs/extensions/releasing/).

### OpenAI Codex — plugin directory

- Self-hosted marketplace installation is confirmed by the supplied installed
  plugin screen. A public OpenAI directory listing was **not verified** on
  **2026-11-23**; a local marketplace entry does not establish directory approval.
- The displayed website uses `interface.websiteURL`; the top-level `homepage`
  alone does not supply that UI field. Set both to
  [the project website](https://ksegit.github.io/Version-Sentinel/), then update
  the installed copy. Source: [plugin submission metadata](https://developers.openai.com/plugins/deploy/submission).
- Plugins with lifecycle hooks are not eligible for the public directory.
  A skills-only submission would be a separate package; it would not include
  this repository's automatic warnings. Source:
  [Build plugins](https://developers.openai.com/plugins/build/plugins).
- [openai-submission.md](openai-submission.md) contains submission materials;
  their presence is not evidence of publication.

### GitHub Copilot CLI — awesome-copilot marketplace

- **Rejected**, checked **2026-11-23**. Submission
  [github/awesome-copilot#2598](https://github.com/github/awesome-copilot/issues/2598)
  passed automated checks for v0.4.1, but a maintainer rejected it on
  **2026-08-11** as not the right fit for the marketplace. The issue is closed
  with the `rejected` label.
- The current [external plugin catalog](https://github.com/github/awesome-copilot/blob/main/plugins/external.json)
  has no `version-sentinel` entry. Do not advertise installation from
  `version-sentinel@awesome-copilot`.
- The successful intake smoke test is evidence that the submitted root
  `plugin.json` was installable, not that a marketplace listing was approved.
  Its recorded `homepage` field supports replacing the old README URL with
  [the project website](https://ksegit.github.io/Version-Sentinel/).

### GitHub Copilot in VS Code / Zed

Repository instructions and skills remain the distribution method documented
here. No Version Sentinel marketplace listing was verified for either editor
on **2026-11-23**. The current
[Zed extensions catalog](https://github.com/zed-industries/extensions/blob/main/extensions.toml)
has no `version-sentinel` entry. This does not mean that either editor lacks
an extension marketplace; it means this integration has not been verified as
listed there. See `docs/zed.md` for the repository integration's limits.

## Third-party directories and pending submissions

These are discovery sites, not evidence of an official platform listing.
The pages below were found through web search on 2026-11-23:

| Directory | Evidence | Limitation |
|-----------|----------|------------|
| [Claude Cowork Plugins](https://www.claudecoworkplugins.com/plugins/ksegit-version-sentinel/) | Direct page returned HTTP 200 and identifies this repository | Description still claims hard blocking |
| [PlugMyPlugin](https://plugmyplugin.com/plugins/ksegit-version-sentinel) | Direct page returned HTTP 200 and links this repository | Description still claims hard blocking |
| [Vibed Lab](https://plugins.vibed-lab.com/plugin/ksegit-version-sentinel) | Search index contains a Version Sentinel listing | Direct request returned HTTP 403; current page not verified |
| [Skillget](https://skillget.dev/listings/ksegit-version-sentinel?lang=en) | Search index contains a Version Sentinel listing | Direct request returned HTTP 403; indexed copy is stale |
| [Claude Plugin Hub](https://www.claudepluginhub.com/skills/ksegit-version-sentinel/version-sentinel) | Search index contains the Version Sentinel skill | Direct request returned HTTP 403; indexed copy is stale |

The [Composio submission issue #205](https://github.com/composio-community/awesome-claude-plugins/issues/205)
remains open. An open submission does not prove catalog publication.
No reliable matching listing was found in the searches of skills.sh or SkillsMP;
this does not prove absence from either service.

Third-party pages can retain old descriptions after repository updates. Their
refresh or correction process must be checked before claiming they are updated.
