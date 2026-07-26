# End-to-End Verification Checklist

Per-platform live e2e status for the multi-agent port. Last live run: **2026-07-26**
(on `feat/multi-agent-support`, macOS, Claude Code 2.1.199, kimi-code current).

Status legend:
- ✅ verified live — command run, expected block/unblock observed
- ⚠️ partially verified — some steps verified live, rest simulated or blocked by environment
- ❌ not verified — CLI not installed on the test machine; steps provided for a manual run

---

## Claude Code — ⚠️ partially verified (2026-07-26)

Steps:

```bash
claude plugin marketplace add /path/to/Version-Sentinel
claude plugin install version-sentinel@version-sentinel-marketplace
claude plugin list      # plugin must show "✔ enabled", Hooks (3) in details

# scratch project
mkdir /tmp/vs-e2e && cd /tmp/vs-e2e
echo '{"name":"e2e","version":"1.0.0","dependencies":{}}' > package.json

# block test (hooks fire under --dangerously-skip-permissions)
claude -p "Add lodash version 4.17.21 to the dependencies in package.json" \
  --output-format stream-json --verbose --dangerously-skip-permissions
# expect: PreToolUse hook blocks Edit/Write, stderr contains "BLOCKED: version-sentinel"

# unblock
bash <installed-plugin-path>/scripts/vs-record.sh npm lodash 4.17.21 https://www.npmjs.com/package/lodash
# re-run the claude -p prompt; package.json must then contain lodash

# cleanup
claude plugin uninstall version-sentinel@version-sentinel-marketplace
claude plugin marketplace remove version-sentinel-marketplace
```

Verified live on 2026-07-26:

- ✅ `marketplace add` + `plugin install` succeed; `plugin details` shows
  `Hooks (3) SessionStart, PreToolUse, PostToolUse`, slash commands
  `version-sentinel:vs-record` / `version-sentinel:check-versions` load in-session.
- ✅ **Critical finding (fixed):** Claude Code *rejected* the combined
  `hooks/hooks.json` containing Gemini keys — `plugin list` showed
  `✘ failed to load / Hook load failed: invalid_key ... path: ["hooks","BeforeTool"]`
  (and `AfterTool`). Claude's loader validates the `hooks` record with a closed
  event enum, and it reads conventional `hooks/hooks.json` **even when**
  `plugin.json` declares a different `hooks` path (verified: pointing
  `plugin.json.hooks` at another file still produced a load error from the
  Gemini-shaped `hooks/hooks.json`). Fix: `hooks/hooks.json` is back to pure
  Claude/Codex schema; Gemini hooks moved to `hooks/gemini-hooks.json`.
  After the fix the plugin shows `✔ enabled`.
- ✅ Hook block + unblock verified at the hook-script level with the exact
  PreToolUse JSON payload Claude passes on stdin:
  `detect-manifest-edit.sh` on a `Write` adding `lodash@4.17.21` → **exit 2**,
  stderr `BLOCKED: version-sentinel. Package: lodash (npm). Version: 4.17.21.`;
  after `vs-record.sh npm lodash 4.17.21 https://www.npmjs.com/package/lodash`
  → **exit 0**. Same for `detect-install-cmd.sh` on `npm install left-pad@1.3.0`
  (exit 2) vs `npm install lodash@4.17.21` post-record (exit 0).
- ❌ Full model-driven `claude -p` run: **blocked by auth** — the CLI on the
  test machine is not logged in (`claude auth status` → `loggedIn: false`;
  `claude -p` returns `Not logged in · Please run /login`). Re-run the two
  `claude -p` steps above on an authenticated machine to close the gap.
  Installed plugin path for step 4:
  `~/.claude/plugins/cache/version-sentinel-marketplace/version-sentinel/<version>/`
  (note: the cache is a *copy* — after changing the repo, uninstall + reinstall
  or update the marketplace before testing).

## Kimi Code — ✅ verified live (2026-07-26) — except TUI plugin install

Kimi has no headless plugin install. Two layers to verify:

**A. Plugin TUI install (manual):**

```
/plugins install https://github.com/KSEGIT/Version-Sentinel   # or a local path
```

Then verify in the TUI: plugin listed as enabled; hooks from
`kimi.plugin.json` registered (SessionStart, PreToolUse Edit|Write|MultiEdit,
PreToolUse Bash, PostToolUse Bash); ask the agent to add a dependency and
confirm the block message appears.

**B. Hook contract (headless-equivalent) — verified live 2026-07-26:**

`KIMI_CODE_HOME` is respected (`KIMI_CODE_HOME=/tmp/vs-kimi-home kimi doctor`
reads `/tmp/vs-kimi-home/config.toml`). The four `[[hooks]]` rules below
(same events/matchers/scripts as `kimi.plugin.json`) validate via `kimi doctor`:

```toml
[[hooks]]
event = "SessionStart"
matcher = "*"
command = "bash /path/to/Version-Sentinel/scripts/prereq-check.sh"
timeout = 10

[[hooks]]
event = "PreToolUse"
matcher = "Edit|Write|MultiEdit"
command = "bash /path/to/Version-Sentinel/scripts/detect-manifest-edit.sh"
timeout = 10

[[hooks]]
event = "PreToolUse"
matcher = "Bash"
command = "bash /path/to/Version-Sentinel/scripts/detect-install-cmd.sh"
timeout = 10

[[hooks]]
event = "PostToolUse"
matcher = "Bash"
command = "bash /path/to/Version-Sentinel/scripts/auto-record.sh"
timeout = 10
```

Notes from the live run:

- `kimi -p ... --yolo` **and** `--auto` are both rejected in prompt mode
  (`Cannot combine --prompt with --yolo/--auto`). Headless auto-approve comes
  from config: set `default_permission_mode = "auto"` (top-level scalar in
  `config.toml`, before any table).
- A scratch `KIMI_CODE_HOME` has no auth (`No model configured ... /login`), so
  the authenticated live run used the real `~/.kimi-code/config.toml` with the
  four rules appended temporarily (restored afterwards, verified identical).
- ✅ **Block:** `kimi -p "Add lodash 4.17.21 to dependencies in package.json"
  --output-format stream-json` in a scratch dir — the `Edit` was blocked; the
  tool result contained `BLOCKED: version-sentinel. Package: lodash (npm).
  Version: 4.17.21. No fresh version check on record (window: 24h).`
- ✅ **Recovery + unblock (same run, model-driven):** the model WebSearched +
  curled `registry.npmjs.org/lodash/latest` (4.18.1), recorded
  `npm/lodash@4.18.1`, retried the 4.17.21 edit → **blocked again** (checks are
  keyed to the exact version — correct), then recorded
  `intentional: user explicitly requested pin 4.17.21` → edit succeeded;
  `package.json` = `{"name":"e2e","version":"1.0.0","dependencies":{"lodash":"4.17.21"}}`.
- **Bug found & fixed during this run:** kimi's `Edit`/`Write` payload uses
  `tool_input.path`, not `tool_input.file_path`, so `detect-manifest-edit.sh`
  silently fail-opened on the first attempt (edit went through unblocked).
  Fixed in `scripts/detect-manifest-edit.sh` (accepts `.path` as fallback);
  regression fixture `tests/fixtures/edit_input_kimi_path.json` added.
- ❌ Not covered: `/plugins install` TUI flow (needs interactive session).

## VS Code — GitHub Copilot — ❌ not verified (2026-07-26)

Copilot agent hooks are **Preview**. Manual steps:

1. VS Code Insiders (or Stable once hooks ship), enable setting
   `chat.hooks.enabled` (preview) — check "GitHub Copilot Chat: Hooks" in Settings.
2. Open this repo (or a copy) as the workspace so `.github/hooks/` and
   `.agents/skills/` are picked up.
3. In Copilot Chat agent mode ask: "Add lodash 4.17.21 to package.json
   dependencies" and confirm the hook blocks / asks for a version check per
   `AGENTS.md`.
4. Record via the documented workflow and retry; confirm success.

## Gemini CLI — ❌ not verified (2026-07-26)

```bash
gemini extensions install https://github.com/KSEGIT/Version-Sentinel   # or a local path
bash ~/.gemini/extensions/version-sentinel/platforms/gemini/setup.sh   # activate hooks
# restart gemini
```

Then ask Gemini to add a dependency to a scratch `package.json` and confirm the
`BeforeTool` block (`BLOCKED: version-sentinel ...`), run `/vs-record ...`,
retry.

**Known issue (found 2026-07-26):** Gemini extensions only auto-load
hooks from the conventional `hooks/hooks.json`, but Claude Code rejects any
`hooks/hooks.json` that contains Gemini keys (closed event enum), and Claude
reads that conventional path even when `plugin.json` points elsewhere. The
Gemini hook definitions therefore live in **`hooks/gemini-hooks.json`**
(Gemini schema: `{"hooks": {SessionStart/BeforeTool/AfterTool}}`), and
`platforms/gemini/setup.sh` copies it over `hooks/hooks.json` *inside the
installed extension copy* (safe: Gemini clones the repo on install; the script
refuses to run outside `~/.gemini/extensions/`). On the first real Gemini
install, also verify that `${extensionPath}` and `${/}` substitution in hook
commands works as assumed, and that `${extensionPath}` is also substituted in
the `commands/*.toml` prompts (if not, the `/vs-record` and `/check-versions`
slash commands will receive a literal `${extensionPath}` — switch them to
`!{...}` shell-injection blocks in that case). Upstream feature request for inline hooks in
`gemini-extension.json` (which would resolve the collision cleanly):
[google-gemini/gemini-cli#25630](https://github.com/google-gemini/gemini-cli/issues/25630).

## OpenAI Codex — ❌ not verified (2026-07-26)

```bash
codex plugin marketplace add KSEGIT/Version-Sentinel   # or a local path
codex plugin add version-sentinel
```

Codex reads `.codex-plugin/plugin.json`, which references
`./hooks/hooks.json` (Claude-schema; Codex accepts this schema, including the
`apply_patch` matcher). Steps:

1. After install, run `/hooks` and complete the **trust review** for the
   plugin's hooks (Codex requires explicit trust before hook commands run).
2. Scratch project with a minimal `package.json`; ask Codex to add
   `lodash@4.17.21` and confirm the PreToolUse block fires (both the Edit path
   and the `apply_patch` path).
3. `bash scripts/vs-record.sh npm lodash 4.17.21 https://www.npmjs.com/package/lodash`,
   retry, confirm success.

## Zed — ❌ not verified (2026-07-26)

Zed has **no hook support** — blocking is best-effort via static permissions +
agent instructions. Manual steps:

1. Open a scratch project; copy or reference this repo's `AGENTS.md` and
   `.agents/skills/`.
2. Follow `docs/zed.md` for the permissions approximation (deny-by-default
   manifest edits where possible).
3. Voluntarily follow the workflow: look up the version on the upstream
   registry, `bash scripts/vs-record.sh ...`, then edit. Verify
   `bash scripts/check-versions.sh` reports no `DRIFT` afterwards.
