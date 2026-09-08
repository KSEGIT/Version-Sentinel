# Distribution & Marketplace Status

Where Version Sentinel can be installed from and listed, per platform — and what
still requires the owner's interactive action. Research date: **2026-09-04**
(refreshed during the marketing pass; see `docs/marketing-plan.md` for the
promotion strategy built on top of this matrix).

Submission status legend:

- **ready-in-repo** — everything needed ships in this repo; install works today
- **requires-owner-form** — mechanism exists, but submission needs the owner's
  logged-in, interactive action (web form / portal / repo settings)
- **not-yet-available** — the platform has announced a directory but self-serve
  publishing is not open
- **no-marketplace** — platform has no listing mechanism; distribution is repo-based
- **channel-closed** — a submission was rejected or the mechanism was withdrawn

## Matrix

| Platform | Install mechanism (verified) | Listing / marketplace | Submission status | Owner next action |
|----------|------------------------------|-----------------------|-------------------|-------------------|
| Claude Code | `/plugin marketplace add https://github.com/KSEGIT/Version-Sentinel.git` → `/plugin install version-sentinel@version-sentinel-marketplace` (self-hosted via `.claude-plugin/marketplace.json`) | Official Claude plugin directory (claude.com/plugins) — **now public**, surfaced in-app as `claude-plugins-official`; updates auto-mirror from the repo after publishing | **requires-owner-form** | Run `claude plugin validate`, then submit at `https://platform.claude.com/plugins/submit` (individual path) using copy from `docs/directory-submission.md` |
| z.ai (GLM Coding Plan / ZCode) | Same as Claude Code — z.ai has no own plugin format; ZCode embeds the Claude Code runtime and the GLM Coding Plan runs inside Claude Code, so the Claude plugin works unchanged | z.ai's `zai-org/zai-coding-plugins` marketplace repo appears **unmaintained** (no upstream push since 2026-02, 23 open issues) | **ready-in-repo** (PR stalled) | Ping or close submission PR [zai-org/zai-coding-plugins#23](https://github.com/zai-org/zai-coding-plugins/pull/23) — open since 2026-07-26 with zero activity; low-value channel |
| Kimi Code | `/plugins install https://github.com/KSEGIT/Version-Sentinel` (or a local path); custom catalog `kimi-marketplace.json` at repo root for `/plugins marketplace <url>` | No official Kimi gallery known — bundled marketplace appears curated by Moonshot; self-hosted catalog is the channel | **ready-in-repo** | Optionally verify the `/plugins marketplace <url>` flow in the TUI (install TUI flow still unverified per `docs/e2e-checklist.md`) |
| Gemini CLI | `gemini extensions install https://github.com/KSEGIT/Version-Sentinel`, then `bash ~/.gemini/extensions/version-sentinel/platforms/gemini/setup.sh` | geminicli.com/extensions gallery — automated daily crawler; **repo not indexed as of 2026-09-04** despite topic + manifest + release tag (known-flaky crawler: issues #28141, #27838) | **requires-owner-form** | Topic `gemini-cli-extension` is set; if still absent from the gallery, file a "valid extension not appearing" issue at google-gemini/gemini-cli |
| OpenAI Codex | `codex plugin marketplace add KSEGIT/Version-Sentinel` → `codex plugin add version-sentinel` (works today from GitHub) | Universal OpenAI Plugins Directory (ChatGPT + Codex) | **requires-owner-form** (portal, self-serve) | Verify developer identity on the OpenAI Platform (**now mandatory**, can take days — start early), then submit via the plugin submission portal (see below) |
| GitHub Copilot CLI | Repo-based install remains possible via ephemeral marketplaces; the awesome-copilot listing was **rejected 2026-08-11** ("not the right fit") — not in `plugins/external.json` | awesome-copilot external plugin marketplace — channel closed for now | **channel-closed** | None — do not resubmit cold; optionally ask the maintainer what would make it a fit |
| GitHub Copilot in VS Code | Repo-based: `.github/` + `.agents/skills/` are picked up when this repo is the workspace, or copy them into yours | None | **no-marketplace** | None — distribution is "use this repo as (part of) your workspace" |
| Zed | Repo-based: `AGENTS.md` + `.agents/skills/` + `docs/zed.md` (static-permissions approximation; no hook support) | None | **no-marketplace** | None |

## Per-platform details and sources

### Claude Code — Anthropic plugin directory

- Submission is **form-only**; there is no PR-based community repo to target.
  As of 2026-09 the directory is **public** at claude.com/plugins and the
  official docs list two submission forms, both requiring sign-in:
  - claude.ai: `https://claude.ai/admin-settings/directory/submissions/plugins/new`
    (requires a Team or Enterprise organization with directory management access)
  - Console: `https://platform.claude.com/plugins/submit`
    (individual authors without a claude.ai org can sign up for Console and
    submit there — **this is our path**)
- Requirements per the docs: public GitHub repo (closed-source not accepted),
  run `claude plugin validate` before submitting. Updates pushed to the repo
  are picked up automatically after publication — no re-submission needed.
- `anthropics/claude-plugins-community` exists but is populated **from** form
  submissions ("Every plugin listed here has been submitted via the form"), so
  it is not an alternative submission channel.
- Ready-to-paste form copy lives in `docs/directory-submission.md`.
- Sources: [Submitting your plugin — Claude docs](https://claude.com/docs/plugins/submit),
  [anthropics/claude-plugins-community](https://github.com/anthropics/claude-plugins-community).

### z.ai (GLM Coding Plan / ZCode)

- z.ai has **no plugin format of its own**. The GLM Coding Plan runs inside
  Claude Code (Anthropic-compatible endpoint), and ZCode — z.ai's desktop
  coding agent — embeds the Claude Code agent runtime, so this repo's Claude
  Code plugin works unchanged on both. No extra files were needed.
- Listing: z.ai maintains [`zai-org/zai-coding-plugins`](https://github.com/zai-org/zai-coding-plugins),
  a Claude-format marketplace repo whose README invites PRs. Submission PR
  [zai-org/zai-coding-plugins#23](https://github.com/zai-org/zai-coding-plugins/pull/23)
  adds `version-sentinel` (source `{"source": "github", "repo":
  "KSEGIT/Version-Sentinel"}`). **As of 2026-09-04 the PR has been open since
  2026-07-26 with zero comments or reviews, and the upstream repo has not been
  pushed to since 2026-02** — the marketplace looks unmaintained. Ping the PR
  once; if there is no reply within two weeks, close it and stop investing in
  this channel.
- ZCode hooks caveat (unverified): ZCode keeps hooks under `~/.zcode/hooks/`
  and `~/.zcode/cli/config.json`; whether it auto-loads a plugin's
  `hooks/hooks.json` like Claude Code does has not been tested (no ZCode
  install available). If not, the workflow degrades to the voluntary flow in
  `AGENTS.md`.
- Sources: [zai-org/zai-coding-plugins](https://github.com/zai-org/zai-coding-plugins),
  [Z.ai tool integration docs](https://docs.z.ai/devpack/tool/others).

### Kimi Code

- Direct install: `/plugins install https://github.com/KSEGIT/Version-Sentinel`.
- `kimi-marketplace.json` at the repo root is a Kimi Code custom marketplace
  catalog (`{"version": "2", "plugins": [...]}` schema); users add it with
  `/plugins marketplace <url-to-kimi-marketplace.json>` and then install
  `version-sentinel` from the catalog. Kept to the documented keys only.
- No official Kimi-hosted gallery is known; the repo catalog is the
  distribution mechanism.

### Gemini CLI — extensions gallery

- The gallery at geminicli.com/extensions **does not accept manual
  submissions** — no PR repo, no form. Per the official releasing guide:
  "The Gemini CLI extension gallery automatically indexes public extensions…
  You don't need to submit an issue or email us." Consequently there is no
  entry format to prepare; no `docs/gemini-gallery-submission.*` file exists.
- Listing requirements (all now satisfied):
  1. Public GitHub repository — true.
  2. GitHub topic **`gemini-cli-extension`** — **done** (set on the repo's
     About section).
  3. `gemini-extension.json` at the repository root — present.
  4. A release tag — present.
- **Indexing status 2026-09-04: not listed.** The repo is absent from
  `https://geminicli.com/extensions.json` even though all requirements are
  met, and it does appear under
  [github.com/topics/gemini-cli-extension](https://github.com/topics/gemini-cli-extension).
  The crawler is known to be flaky (google-gemini/gemini-cli issues #28141,
  #27838). If it is still missing after a few more days, file a "valid
  extension not appearing in gallery" issue at google-gemini/gemini-cli.
- Hooks note: after `gemini extensions install`, hooks must be activated with
  `bash ~/.gemini/extensions/version-sentinel/platforms/gemini/setup.sh` —
  see `docs/e2e-checklist.md` for why (`hooks/hooks.json` schema collision
  with Claude Code).
- Sources: [Release extensions — Gemini CLI docs](https://geminicli.com/docs/extensions/releasing/),
  [Gemini CLI extensions docs](https://geminicli.com/docs/extensions/).

### OpenAI Codex — plugin directory

- Repo-based install works today: `codex plugin marketplace add
  KSEGIT/Version-Sentinel` → `codex plugin add version-sentinel`
  (`.codex-plugin/plugin.json`; legacy fallback reads `.claude-plugin/marketplace.json`).
- Directory publishing is **no longer "coming soon"** — self-serve submission
  is available via the OpenAI Platform **plugin submission portal**
  (linked from [Submit plugins](https://developers.openai.com/plugins/deploy/submission)).
  Approved plugins appear in the universal Plugins Directory shared by
  ChatGPT and Codex.
- Prerequisites that make this owner-action-only:
  - An organization role with **Apps Management: Write** (owners have it).
  - A **verified developer or business identity** on the OpenAI Platform.
  - Submission materials: listing copy, logo, website/support/privacy/terms
    URLs, starter prompts, and 5 positive + 3 negative test cases.
- Submission type resolved: **Skills only**. Hooks are not a submittable
  portal component, so a directory listing ships the `version-sentinel` skill
  archive (`version-sentinel-openai-skill.zip` containing `skills/version-sentinel/`
  plus the required `scripts/` directory with `scripts/lib/` dependencies) and
  cannot enforce blocking; hook-based enforcement stays a property of the
  repo-installed plugin. Repo-marketplace install remains the fallback either way.
- **Paste-ready listing copy, test cases, and the portal walkthrough live in
  [openai-submission.md](openai-submission.md).** Privacy and Terms URLs now
  point to PRIVACY.md and TERMS.md in the repo.
- Sources: [Codex plugins overview](https://developers.openai.com/codex/plugins),
  [Submit plugins — OpenAI Developers](https://developers.openai.com/plugins/deploy/submission).

### GitHub Copilot CLI — awesome-copilot marketplace

- The [github/awesome-copilot](https://github.com/github/awesome-copilot)
  collection lists external plugins in `plugins/external.json`; public
  contributors must **not** PR that file directly — submission is an
  issue-form workflow (`[External Plugin]:` issue) with automated intake
  (`vally lint` + a Copilot CLI install smoke test + version/ref-sha
  consistency gates), then maintainer `/approve` opens the listing PR.
- Submitted 2026-08-09 as
  [github/awesome-copilot#2598](https://github.com/github/awesome-copilot/issues/2598)
  for `version-sentinel` 0.4.1. All automated gates passed, but a maintainer
  **rejected it on 2026-08-11** (`/reject This isn't the right fit for the
  marketplace at this point in time.`) and the issue was closed. Verified
  2026-09-04: `version-sentinel` is not in `plugins/external.json`.
  Do not resubmit cold; the bot's `/rerun-intake` path will not change the
  maintainer's judgement. At most, ask what would make it a fit.
- Historical intake notes (kept in case the channel reopens):
  - Gotcha hit during intake: leaving `/` in the form's *Plugin path* field
    produces `source.path: "/"`, which the Copilot CLI smoke test rejects
    ("Plugin path escapes repository directory") — leave the field empty for
    a root plugin.
  - Non-blocking spec warnings remain: our `plugin.json` carries Claude
    Code top-level fields (`skills`, `agents`, `commands`, `userConfig`)
    outside Agent Plugins v1.0.0. They are required by the other platforms;
    do not "fix" them for this listing.
- After approval, a nightly job marks approved listings as due for re-review
  every six months; a maintainer then performs the actual review on the
  original issue (`/re-review-keep` et al. are maintainer commands).
- The gates can be rehearsed locally before any resubmission: clone
  awesome-copilot, `cd` into it, verify the upstream version of
  `@github/copilot` (currently 1.0.78), record it with
  `bash scripts/vs-record.sh npm @github/copilot 1.0.78 https://www.npmjs.com/package/@github/copilot`,
  then run `npm install` and
  `node eng/external-plugin-quality-gates.mjs --plugin-json '<entry json>'`
  with `copilot` on PATH (`@github/copilot` npm package).

### GitHub Copilot in VS Code / Zed

Neither platform has a plugin marketplace or directory for this kind of
artifact. Distribution is repo-based: users open this repo as their workspace
(Copilot) or copy `AGENTS.md` / `.agents/skills/` into their project (Copilot,
Zed). Nothing to submit.

## Community directories and awesome lists

Cheap, high-signal channels found in the 2026-09-04 marketing research. None
are platform marketplaces, but they are where users actually discover plugins.

- **[claudedirectory.org](https://claudedirectory.org/)** — community Claude
  Code directory (plugins, skills, hooks) with fresh Aug-2026 listings;
  accepts GitHub-based submissions. Not yet listed; submit.
- **[hesreallyhim/awesome-claude-code](https://github.com/hesreallyhim/awesome-claude-code)** —
  the main curated Claude Code list; relaunched in a new format and re-adding
  resources. `version-sentinel` fits the Security or Linting categories.
  Not listed; follow the repo's recommendation process.
- **[Piebald-AI/awesome-gemini-cli](https://github.com/Piebald-AI/awesome-gemini-cli)** —
  accepts PRs to its "Commands & Extensions" section. Not listed; open a PR.
