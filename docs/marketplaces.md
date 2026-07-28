# Distribution & Marketplace Status

Where Version Sentinel can be installed from and listed, per platform — and what
still requires the owner's interactive action. Research date: **2026-07-26**
(on `feat/multi-agent-support`, the multi-agent port targeting v0.3.0).

Submission status legend:

- **ready-in-repo** — everything needed ships in this repo; install works today
- **requires-owner-form** — mechanism exists, but submission needs the owner's
  logged-in, interactive action (web form / portal / repo settings)
- **not-yet-available** — the platform has announced a directory but self-serve
  publishing is not open
- **no-marketplace** — platform has no listing mechanism; distribution is repo-based

## Matrix

| Platform | Install mechanism (verified) | Listing / marketplace | Submission status | Owner next action |
|----------|------------------------------|-----------------------|-------------------|-------------------|
| Claude Code | `/plugin marketplace add https://github.com/KSEGIT/Version-Sentinel.git` → `/plugin install version-sentinel@version-sentinel-marketplace` (self-hosted via `.claude-plugin/marketplace.json`) | Official Claude plugin directory (claude.com/plugins), surfaced in-app as `claude-plugins-official` | **requires-owner-form** | Run `claude plugin validate`, then submit the in-app form (see below) using copy from `docs/directory-submission.md` |
| z.ai (GLM Coding Plan / ZCode) | Same as Claude Code — z.ai has no own plugin format; ZCode embeds the Claude Code runtime and the GLM Coding Plan runs inside Claude Code, so the Claude plugin works unchanged | z.ai maintains `zai-org/zai-coding-plugins`, a Claude-format marketplace repo that accepts PRs | **ready-in-repo** (PR submitted) | None — submission PR [zai-org/zai-coding-plugins#23](https://github.com/zai-org/zai-coding-plugins/pull/23) opened 2026-07-26; track merge |
| Kimi Code | `/plugins install https://github.com/KSEGIT/Version-Sentinel` (or a local path); custom catalog `kimi-marketplace.json` at repo root for `/plugins marketplace <url>` | No official Kimi gallery known — self-hosted catalog | **ready-in-repo** | Optionally verify the `/plugins marketplace <url>` flow in the TUI (install TUI flow still unverified per `docs/e2e-checklist.md`) |
| Gemini CLI | `gemini extensions install https://github.com/KSEGIT/Version-Sentinel`, then `bash ~/.gemini/extensions/version-sentinel/platforms/gemini/setup.sh` | geminicli.com/extensions gallery — **fully automated daily crawler**, no PR and no form | **requires-owner-form** (one repo-setting change) | Add the GitHub topic `gemini-cli-extension` to the repo's About section; the crawler lists it within ~24h |
| OpenAI Codex | `codex plugin marketplace add KSEGIT/Version-Sentinel` → `codex plugin add version-sentinel` (works today from GitHub) | Universal OpenAI Plugins Directory (ChatGPT + Codex) | **requires-owner-form** (portal, now self-serve) | Verify developer identity on the OpenAI Platform, then submit via the plugin submission portal (see below) |
| GitHub Copilot in VS Code | Repo-based: `.github/` + `.agents/skills/` are picked up when this repo is the workspace, or copy them into yours | None | **no-marketplace** | None — distribution is "use this repo as (part of) your workspace" |
| Zed | Repo-based: `AGENTS.md` + `.agents/skills/` + `docs/zed.md` (static-permissions approximation; no hook support) | None | **no-marketplace** | None |

## Per-platform details and sources

### Claude Code — Anthropic plugin directory

- Submission is **form-only**; there is no PR-based community repo to target.
  The official docs list two in-app submission forms, both requiring sign-in:
  - claude.ai: `https://claude.ai/admin-settings/directory/submissions/plugins/new`
    (requires a Team or Enterprise organization with directory management access)
  - Console: `https://platform.claude.com/plugins/submit`
    (individual authors without a claude.ai org can sign up for Console and
    submit there)
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
  "KSEGIT/Version-Sentinel"}`) — opened 2026-07-26, track its merge.
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
- Listing requirements (all satisfiable from this repo except the topic):
  1. Public GitHub repository — already true.
  2. GitHub topic **`gemini-cli-extension`** on the repo's About section —
     **owner action** (repo settings, or
     `gh repo edit KSEGIT/Version-Sentinel --add-topic gemini-cli-extension`).
  3. `gemini-extension.json` at the repository root — already present.
- The crawler scans tagged repositories daily; expect listing within ~24h of
  adding the topic.
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
- Open question for the owner: the portal's submission types are "Skills only"
  and "With MCP" — a skills-only submission (bundle `skills/version-sentinel/`
  + the workflow docs) is the plausible fit; plugin **hooks** are documented
  as a plugin component but are not called out as a submittable part of the
  portal flow, so the hooks-based blocking may not be representable in a
  directory listing. Evaluate in the portal; repo-marketplace install remains
  the fallback either way.
- Sources: [Codex plugins overview](https://developers.openai.com/codex/plugins),
  [Submit plugins — OpenAI Developers](https://developers.openai.com/plugins/deploy/submission).

### GitHub Copilot in VS Code / Zed

Neither platform has a plugin marketplace or directory for this kind of
artifact. Distribution is repo-based: users open this repo as their workspace
(Copilot) or copy `AGENTS.md` / `.agents/skills/` into their project (Copilot,
Zed). Nothing to submit.
