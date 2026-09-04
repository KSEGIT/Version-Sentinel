# Marketing Plan — Version Sentinel

Research date: **2026-09-04** (four parallel web-research passes: marketplaces,
Reddit, Stack Overflow, Discord). Sources are cited per section. This plan
supersedes the channel guesses in `docs/marketplaces.md` where they conflict.

## Current state

- Latest release: **v0.4.4** (2026-09-02). Repo: 3 stars, 0 forks, 0 watchers.
- The `gemini-cli-extension` topic is already set on the repo.
- The product is solid; the problem is distribution. No channel has produced
  installs yet, and one listing attempt (awesome-copilot) was rejected.

## What changed since the July/August research

| Channel | Change | Source |
|---------|--------|--------|
| Anthropic plugin directory | Now public at claude.com/plugins; self-serve submit at `platform.claude.com/plugins/submit`; repo updates auto-mirror after publishing | claude.com/docs/plugins/submit |
| awesome-copilot | Issue #2598 **rejected** 2026-08-11 ("not the right fit"). Resubmission unlikely without maintainer buy-in | github.com/github/awesome-copilot/issues/2598 |
| z.ai marketplace | PR #23 still open; upstream repo untouched since 2026-02 — **unmaintained**. Ping once or close | github.com/zai-org/zai-coding-plugins/pull/23 |
| Gemini gallery | Repo **not indexed** despite topic + manifest + release tag. Known-flaky crawler (issues #28141, #27838) | geminicli.com/extensions.json |
| OpenAI portal | Identity verification now mandatory; needs "Apps Management: Write" role; 5 positive + 3 negative test cases | developers.openai.com/plugins/deploy/submission |
| New: claudedirectory.org | Community Claude plugin directory, active (Aug 2026 listings), accepts GitHub submissions | claudedirectory.org |
| New: awesome lists | awesome-claude-code (relaunched, re-adding resources) and awesome-gemini-cli accept PRs | github.com/hesreallyhim/awesome-claude-code |

## Positioning

One message, everywhere: **AI agents install package versions from memory —
sometimes versions that never existed. Attackers register those names
(slopsquatting). Version Sentinel is the hook that forces the agent to check
the registry before it writes.**

Use numbers, not adjectives. The timely hook: The Register's 2026-08-20 story
of an engineer who nearly installed malware via an AI-hallucinated package
name. Fresh slopsquatting threads are running on Reddit right now.

## Required asset before any launch post

**Demo media** — Reddit dev-tool launches without a demo underperform badly.
Two assets now exist (recorded 2026-09-04):

- `assets/demo.gif` — terminal demo of the real hooks: Claude Code tries
  `npm install lodash@4.17.21` from memory → exit 2 block → registry check
  (4.18.1) → `/vs-record` with the npmjs.com URL → verified install passes,
  stale version stays blocked. Top of README.md.
- `assets/anim/explainer.mp4` / `.gif` — 14 s human-friendly explainer
  (agent → memory version → BLOCKED stamp → live registry check → verified
  version lands in package.json). Use the MP4 for Reddit/Discord native
  video, the GIF where video is not supported.

## Launch sequence

### Phase 0 — Repo polish (agent does, no logins)

1. Update `docs/marketplaces.md` with the status changes above. *(done in
   this branch)*
2. Record the demo GIF; add it to README.md. *(done: `assets/demo.gif` —
   terminal demo of the real hooks, source in `assets/demo/demo.sh`)*
3. Human-friendly explainer animation for social posts. *(done:
   `assets/anim/explainer.gif` for README/docs, `assets/anim/explainer.mp4`
   for Reddit/Discord native video; deterministic source in
   `assets/anim/explainer.html` — re-render via Playwright seek + ffmpeg)*
4. Add repo social preview image (owner: repo Settings → Social preview;
   `assets/hero.png` is ready to upload).

### Phase 1 — Marketplaces and lists (mix of owner logins and agent work)

Priority order:

1. **Anthropic plugin directory** (highest reach). Owner login at
   `platform.claude.com/plugins/submit`. Agent: run `claude plugin validate`
   first, prepare copy from `docs/directory-submission.md`, drive the form in
   the browser once the owner is logged in.
2. **OpenAI plugin portal** (skills-only). Owner: verify developer identity on
   the OpenAI Platform first — that step can take days, so start it early.
   Copy and test cases are ready in `docs/openai-submission.md`.
3. **claudedirectory.org** — submit via their GitHub flow. Agent can do this
   with the repo owner's GitHub auth (`gh`).
4. **awesome-claude-code** — follow its recommendation process.
5. **awesome-gemini-cli** — PR to the "Commands & Extensions" section.
6. **Gemini gallery** — confirm topic + tag (both present), then file a
   "valid extension not appearing in gallery" issue at google-gemini/gemini-cli
   if still absent after 48 h.
7. **z.ai PR #23** — leave one polite ping comment; if no reply in 2 weeks,
   close it and stop investing there.
8. **awesome-copilot** — dropped. Optionally ask the maintainer what would
   make it a fit; do not resubmit cold.

### Phase 2 — Reddit (owner login, agent drafts and posts)

Account prep (week 0–1): the owner's Reddit account needs karma and age.
Warm it with genuine comments in r/ClaudeCode and r/ChatGPTCoding. Keep
self-promo under ~10% of account activity.

Posting plan (one post per sub, staggered, Tue–Thu 14:00–17:00 UTC, owner
present to answer comments):

| Week | Subreddit | Notes |
|------|-----------|-------|
| 1 | r/coolgithubprojects, r/SideProject | Promo explicitly allowed; low karma gates; story-first post |
| 2 | r/ClaudeCode (~382K) | Rule 6: disclose authorship, state cost (free/MIT), no repeat promotion |
| 2 | r/ChatGPTCoding (~375K) | **Weekly self-promo thread only** |
| 3 | r/ClaudeAI (1.1M) | **Modmail first** for permission |
| 3 | r/opensource (~376K) | One clean post, no drip feed |

Do NOT post to r/programming (promo banned), r/netsec (monthly tool thread
only), r/vibecoding (needs X.com pre-approval), or the language subs.

Also: comment-level engagement on active slopsquatting threads (real,
non-archived ones found via a live `slopsquatting` search sorted by New).
Answer the problem first; mention the tool with disclosure only where it fits.

Draft copy lives in the appendix below.

### Phase 3 — Discord (owner login, agent posts)

Join and read each server's rules channel **before** posting; most internals
are not publicly documented.

1. **Anthropic official** — `discord.gg/anthropic` (~62K, has Claude Code
   channels and office hours). Highest value. Beware phishing clones; the
   real server never asks for wallet connections.
2. **Moonshot/Kimi official** — `discord.com/invite/TYU2fdJykW`. Smaller,
   direct fit (Kimi Code supported), better visibility per post.
3. **Cline** — `discord.gg/cline`. Agentic-coding power users; good feedback
   even though Cline is not a supported platform.
4. **OpenAI** — `discord.gg/openai`. Codex angle; big but noisy.

Skip: The Programmer's Hangout (advertising banned), Reactiflux (weak JS fit,
tenure-gated), Google (no official Discord exists). Latent Space only after
genuine participation, never as a cold pitch.

Post format: 2–3 sentences in the showcase/promo channel — the problem, what
the plugin does, one link. Then stay and answer questions.

Bonus, not Discord: **OpenSSF** runs a Tech Talks webinar program and a
~12K-subscriber newsletter that amplifies member projects — a strong route
for the supply-chain-security angle (openssf.org, Slack-based).

### Phase 4 — Q&A (low effort, run in background)

- Stack Overflow verdict: **hygiene, not growth.** The `claude-code` tag has
  37 questions ever; zero slopsquatting posts network-wide. Question volume
  there has collapsed since ChatGPT.
- Do exactly one exemplary answer:
  [q/79747164 — settings.json deny block not respected](https://stackoverflow.com/questions/79747164).
  Solve it tool-free with a minimal PreToolUse hook, then one disclosed
  sentence: "I maintain an MIT plugin that does this for dependency
  installs." Follow stackoverflow.com/help/promotion exactly.
- Set tag watches: `claude-code`, `gemini-cli`, keyword filters
  `hallucinat*`, `typosquat`, `slopsquat`.
- Claim SO's **free community promotion ads** for open-source projects —
  zero-risk official channel.

### Phase 5 — Optional amplifiers

- **Show HN**: "Show HN: Version Sentinel — blocks AI agents from installing
  hallucinated packages." Highest-leverage single post for this category;
  slopsquatting posts repeatedly hit the front page. Post Tue–Thu morning ET,
  owner present for comments.
- **dev.to / blog post**: the slopsquatting story + how the hook works. This
  is the only format r/programming tolerates, and it feeds every other
  channel.

## What the agent needs from the owner (logins)

| When | Login |
|------|-------|
| Phase 1 step 1 | Anthropic Console (`platform.claude.com`) |
| Phase 1 step 2 | OpenAI Platform (identity verification is owner-only) |
| Phase 2 | Reddit account (warmed up, see above) |
| Phase 3 | Discord account joined to the 4 servers |
| Phase 5 | HN account (aged accounts rank better) |

The agent can drive all browser forms and posts via Playwright once the owner
is logged in in the browser profile.

## Risks

- **Reddit bans** — the top failure mode. Mitigations: disclosure in every
  post, one post per sub, staggered weeks, modmail where required, no
  cross-posted identical text, 90/10 activity rule.
- **Discord removal** — post only in designated showcase channels, never in
  general.
- **Demo GIF missing** — delays everything; it is the Phase 0 blocker.
- **OpenAI identity verification latency** — start it before anything else in
  Phase 1.

---

## Appendix A — Reddit copy drafts

Adapt per sub; never cross-post identical text.

### r/SideProject / r/coolgithubprojects (story-first)

Title: `I caught my AI agent installing a package that doesn't exist — so I built a plugin that blocks it`

Body:

> A few weeks ago Claude Code tried to add a version of an npm package that
> had never been published. The model remembered it from training data. If
> that version name had been registered by an attacker (this is a real attack
> now — it's called slopsquatting), I would have installed malware with one
> Enter key.
>
> So I built Version Sentinel: an open-source (MIT) hook for AI coding agents
> that hard-blocks any dependency add, bump, downgrade, or install until the
> agent has looked up the real latest version on npm, PyPI, crates.io, or
> NuGet and recorded where it checked. The tool call itself is refused (exit
> 2) until the check is on record. Intentional pins are supported.
>
> Works with Claude Code, Kimi Code, Gemini CLI, OpenAI Codex, and as
> repo-level instructions for Copilot and Zed.
>
> Happy to answer questions — and I'd genuinely like feedback on whether a
> hard block is too aggressive for your workflow.
>
> [demo GIF] https://github.com/KSEGIT/Version-Sentinel

### r/ClaudeCode (Rule 6 disclosure)

Title: `I built a Claude Code plugin that hard-blocks dependency installs until Claude verifies the version against the registry (free, MIT)`

Body: same story, shorter; explicit disclosure line first:

> Disclosure: I built this, it's free and MIT-licensed, no cost or signup.

### r/ChatGPTCoding (weekly self-promo thread only)

One short paragraph + link + GIF. No story.

## Appendix B — Discord copy

> I kept hitting a problem where Claude Code would add package versions from
> memory — including versions that don't exist (which is exactly the
> slopsquatting attack). So I wrote Version Sentinel, an MIT plugin that
> hard-blocks dependency edits and installs until the agent records a fresh
> registry check. Supports npm / PyPI / Cargo / NuGet across Claude Code,
> Kimi Code, Gemini CLI, and Codex. Feedback welcome:
> https://github.com/KSEGIT/Version-Sentinel

## Appendix C — Stack Overflow answer skeleton (q/79747164)

1. Explain why `settings.json` deny patterns miss the OP's case.
2. Show a minimal working PreToolUse hook (bash + JSON, self-contained).
3. One sentence: "If you want this pre-built for dependency installs across
   Claude Code / Gemini CLI / Codex, I maintain an MIT-licensed plugin,
   Version Sentinel, that does exactly this." + link.

## Appendix D — Show HN draft

Title: `Show HN: Version Sentinel – blocks AI agents from installing hallucinated packages`

First comment (the story): what happened, why training-cutoff versions are
dangerous, how the hook works, what it does not do (advisory tools exist;
this is enforcement inside the agent loop).
