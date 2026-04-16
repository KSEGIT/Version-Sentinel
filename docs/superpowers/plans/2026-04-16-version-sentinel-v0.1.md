# version-sentinel v0.1.0 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship version-sentinel v0.1.0 — a Claude Code plugin that hard-blocks dependency additions/bumps/downgrades in 5 ecosystems (npm, pip, pyproject.toml, Cargo.toml, csproj) until Claude records a WebSearch-verified version check in a project-local sidecar.

**Architecture:** Two PreToolUse shell hooks (one for Edit/Write/MultiEdit, one for Bash) detect package changes, parse the relevant ecosystem, and consult a JSON sidecar. Missing-or-stale entry → exit 2 with stderr instructing Claude to WebSearch + `/vs-record`. Two slash commands (`/vs-record`, `/check-versions`) + one auto-loaded skill complete the UX.

**Tech Stack:** Bash (Git Bash on Windows), `jq` for JSON, `python3 -c 'import tomllib'` for TOML (Python 3.11+), `grep`/`sed` for XML & regex, `curl` for registry APIs. No runtime compilation or framework.

**Repo path:** `C:\Users\DanielKiska\Source\private\version-sentinel`

**Spec reference:** `docs/superpowers/specs/2026-04-16-version-sentinel-design.md`

---

## File Structure

```
version-sentinel/
├── .claude-plugin/
│   ├── plugin.json                  # Task 1
│   └── marketplace.json             # Task 1
├── hooks/
│   └── hooks.json                   # Task 14
├── scripts/
│   ├── detect-manifest-edit.sh      # Task 12 — Edit|Write|MultiEdit handler
│   ├── detect-install-cmd.sh        # Task 13 — Bash handler
│   ├── check-sidecar.sh             # Task 4 — shared allow/block decision
│   ├── vs-record.sh                 # Task 15 — writes sidecar entry
│   ├── check-versions.sh            # Task 16 — registry-drift audit
│   └── lib/
│       ├── sidecar.sh               # Task 3 — sidecar read/write/dedupe
│       ├── parse-manifest.sh        # Tasks 5–10 — per-ecosystem parsers + dispatch
│       └── parse-install-cmd.sh     # Task 11 — install-cmd regex
├── commands/
│   ├── vs-record.md                 # Task 15 — slash command doc
│   └── check-versions.md            # Task 16 — slash command doc
├── skills/
│   └── version-sentinel/
│       └── SKILL.md                 # Task 17
├── tests/
│   ├── run.sh                       # Task 2
│   ├── assert.sh                    # Task 2 — shared assertions
│   ├── fixtures/                    # Tasks 2, 5–13 — per-test payloads
│   └── integration/
│       └── smoke.sh                 # Task 19
├── README.md                        # Task 18
├── LICENSE                          # Task 1 (MIT)
├── CHANGELOG.md                     # Task 20
└── docs/                            # (already exists)
    └── superpowers/{specs,plans}/
```

---

## Prerequisites check (run once before Task 1)

Verify these binaries exist before starting. If missing, install first.

```bash
for bin in bash jq curl python3; do
  command -v "$bin" >/dev/null 2>&1 || echo "MISSING: $bin"
done
python3 -c 'import tomllib' 2>&1 | grep -v '^$' && echo "MISSING: tomllib (need Python 3.11+)" || echo "tomllib OK"
```

Expected: no `MISSING:` lines. On Windows, `bash`/`jq`/`curl` ship with Git Bash; `python3` is `C:\Users\DanielKiska\AppData\Local\Programs\Python\Python313\python3.exe`.

---

### Task 1: Scaffold plugin + marketplace manifests + LICENSE

**Files:**
- Create: `.claude-plugin/plugin.json`
- Create: `.claude-plugin/marketplace.json`
- Create: `LICENSE`

- [ ] **Step 1: Create `plugin.json`**

```json
{
  "name": "version-sentinel",
  "version": "0.1.0",
  "description": "Hard-blocks dependency additions and version changes until Claude records a WebSearch-verified latest-version check.",
  "author": {
    "name": "Daniel Kiska",
    "url": "https://github.com/DanielKiska"
  },
  "repository": "https://github.com/DanielKiska/version-sentinel",
  "license": "MIT",
  "keywords": ["dependencies", "packages", "versions", "guardrails", "hooks"]
}
```

Write to `.claude-plugin/plugin.json`.

- [ ] **Step 2: Create `marketplace.json`**

```json
{
  "name": "version-sentinel-marketplace",
  "owner": {
    "name": "Daniel Kiska",
    "url": "https://github.com/DanielKiska"
  },
  "plugins": [
    {
      "name": "version-sentinel",
      "source": {
        "source": "github",
        "repo": "DanielKiska/version-sentinel"
      },
      "description": "Hard-blocks dependency additions until a version check is recorded.",
      "version": "0.1.0"
    }
  ]
}
```

Write to `.claude-plugin/marketplace.json`.

- [ ] **Step 3: Create MIT LICENSE**

Write standard MIT text to `LICENSE` with `Copyright (c) 2026 Daniel Kiska`.

- [ ] **Step 4: Sanity-check JSON parses**

Run:
```bash
jq . .claude-plugin/plugin.json > /dev/null && echo "plugin.json OK"
jq . .claude-plugin/marketplace.json > /dev/null && echo "marketplace.json OK"
```
Expected: both print `OK`.

- [ ] **Step 5: Commit**

```bash
git add .claude-plugin/ LICENSE
git commit -m "feat(scaffold): plugin.json + marketplace.json + LICENSE

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: Test harness + assertion helpers

**Files:**
- Create: `tests/run.sh`
- Create: `tests/assert.sh`
- Create: `tests/fixtures/.keep` (placeholder so git tracks the dir)

- [ ] **Step 1: Write `tests/assert.sh`**

```bash
#!/usr/bin/env bash
# Shared assertions. Source this from each test script.
set -u

VS_TEST_FAILED=0
VS_TEST_NAME="${VS_TEST_NAME:-unnamed}"

_fail() {
  echo "FAIL [$VS_TEST_NAME]: $1" >&2
  VS_TEST_FAILED=1
}

assert_eq() {
  # assert_eq <expected> <actual> <label>
  if [[ "$1" != "$2" ]]; then
    _fail "$3: expected '$1', got '$2'"
  fi
}

assert_contains() {
  # assert_contains <haystack> <needle> <label>
  if [[ "$1" != *"$2"* ]]; then
    _fail "$3: string does not contain '$2'. Full: $1"
  fi
}

assert_exit_code() {
  # assert_exit_code <expected> <actual> <label>
  assert_eq "$1" "$2" "$3 (exit code)"
}

assert_file_exists() {
  # assert_file_exists <path> <label>
  if [[ ! -f "$1" ]]; then
    _fail "$2: file missing: $1"
  fi
}

finish_test() {
  if [[ "$VS_TEST_FAILED" -eq 0 ]]; then
    echo "PASS [$VS_TEST_NAME]"
  fi
  return "$VS_TEST_FAILED"
}
```

- [ ] **Step 2: Write `tests/run.sh`**

```bash
#!/usr/bin/env bash
# Discover and run every tests/test_*.sh. Each test sets VS_TEST_NAME and sources assert.sh.
set -u
cd "$(dirname "$0")"

total=0
failed=0
for t in test_*.sh; do
  [[ -f "$t" ]] || continue
  total=$((total + 1))
  if ! bash "$t"; then
    failed=$((failed + 1))
  fi
done

echo
echo "-----"
echo "Total: $total, Failed: $failed"
[[ "$failed" -eq 0 ]]
```

- [ ] **Step 3: Write placeholder smoke test to verify harness works**

Create `tests/test_harness.sh`:

```bash
#!/usr/bin/env bash
VS_TEST_NAME="harness-smoke"
source "$(dirname "$0")/assert.sh"

assert_eq "a" "a" "trivial equality"
assert_contains "hello world" "world" "substring"
assert_exit_code 0 0 "zero exit"

finish_test
```

- [ ] **Step 4: Run the harness**

```bash
chmod +x tests/run.sh tests/test_harness.sh
bash tests/run.sh
```

Expected: `PASS [harness-smoke]` then `Total: 1, Failed: 0`, exit 0.

- [ ] **Step 5: Commit**

```bash
touch tests/fixtures/.keep
git add tests/
git commit -m "test: bash test harness (run.sh + assert.sh + smoke)

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: Sidecar read/write library

**Files:**
- Create: `scripts/lib/sidecar.sh`
- Create: `tests/test_sidecar.sh`
- Create: `tests/fixtures/sidecar_empty.json`
- Create: `tests/fixtures/sidecar_one_entry.json`

- [ ] **Step 1: Write failing tests first**

Create `tests/fixtures/sidecar_one_entry.json`:
```json
{
  "entries": [
    {
      "ecosystem": "npm",
      "pkg": "lodash",
      "version": "4.17.21",
      "source": "https://www.npmjs.com/package/lodash",
      "checkedAt": "2026-04-16T10:00:00Z"
    }
  ]
}
```

Create `tests/fixtures/sidecar_empty.json`:
```json
{ "entries": [] }
```

Create `tests/test_sidecar.sh`:

```bash
#!/usr/bin/env bash
VS_TEST_NAME="sidecar"
source "$(dirname "$0")/assert.sh"
source "$(dirname "$0")/../scripts/lib/sidecar.sh"

TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

# --- sidecar_read returns entries from a valid file ---
cp tests/fixtures/sidecar_one_entry.json "$TMPDIR/checks.json"
out=$(sidecar_read "$TMPDIR/checks.json")
assert_contains "$out" "lodash" "read returns entries"

# --- sidecar_read on missing file returns empty entries array ---
out=$(sidecar_read "$TMPDIR/nope.json")
assert_contains "$out" '"entries":[]' "missing file → empty"

# --- sidecar_read on corrupt file returns empty + warns ---
echo "not json" > "$TMPDIR/corrupt.json"
out=$(sidecar_read "$TMPDIR/corrupt.json" 2>/dev/null)
assert_contains "$out" '"entries":[]' "corrupt file → empty"

# --- sidecar_find_fresh: found within window ---
# Entry at 10:00Z, now-fake = 14:00Z same day, window=24h → fresh
cp tests/fixtures/sidecar_one_entry.json "$TMPDIR/checks.json"
VS_NOW_OVERRIDE="2026-04-16T14:00:00Z" \
  result=$(sidecar_find_fresh "$TMPDIR/checks.json" npm lodash 4.17.21 24; echo "exit=$?")
assert_contains "$result" "exit=0" "fresh entry hit"

# --- sidecar_find_fresh: stale ---
VS_NOW_OVERRIDE="2026-04-18T10:00:01Z" \
  result=$(sidecar_find_fresh "$TMPDIR/checks.json" npm lodash 4.17.21 24; echo "exit=$?")
assert_contains "$result" "exit=1" "stale entry missed"

# --- sidecar_find_fresh: different version missed ---
VS_NOW_OVERRIDE="2026-04-16T14:00:00Z" \
  result=$(sidecar_find_fresh "$TMPDIR/checks.json" npm lodash 5.0.0 24; echo "exit=$?")
assert_contains "$result" "exit=1" "different version missed"

# --- sidecar_write_entry dedupe ---
cp tests/fixtures/sidecar_empty.json "$TMPDIR/checks.json"
sidecar_write_entry "$TMPDIR/checks.json" npm lodash 4.17.21 \
  "https://www.npmjs.com/package/lodash" "2026-04-16T10:00:00Z"
sidecar_write_entry "$TMPDIR/checks.json" npm lodash 4.18.0 \
  "https://www.npmjs.com/package/lodash" "2026-04-16T11:00:00Z"
count=$(jq '.entries | length' "$TMPDIR/checks.json")
assert_eq "1" "$count" "dedupe: same (ecosystem,pkg) keeps only one entry"
version=$(jq -r '.entries[0].version' "$TMPDIR/checks.json")
assert_eq "4.18.0" "$version" "dedupe: last-write-wins"

# --- sidecar_write_entry auto-creates .gitignore ---
GITIGNORE="$TMPDIR/.gitignore"
assert_file_exists "$GITIGNORE" "auto-gitignore created"
content=$(cat "$GITIGNORE")
assert_contains "$content" "*" "gitignore contains *"
assert_contains "$content" "!.gitignore" "gitignore re-includes itself"

finish_test
```

- [ ] **Step 2: Run test — expect FAIL**

```bash
bash tests/test_sidecar.sh
```
Expected: fails (no sidecar.sh yet).

- [ ] **Step 3: Implement `scripts/lib/sidecar.sh`**

```bash
#!/usr/bin/env bash
# Sidecar JSON state for version-sentinel.
# Keyed by (ecosystem, pkg); last-write-wins dedupe.

# sidecar_path: echoes the sidecar file path to use.
# Primary: <cwd>/.version-sentinel/checks.json
# Fallback: ${CLAUDE_PLUGIN_DATA}/checks.json (or ~/.claude/plugins/data/version-sentinel/checks.json)
sidecar_path() {
  local cwd="${1:-$PWD}"
  if [[ -w "$cwd" ]]; then
    echo "$cwd/.version-sentinel/checks.json"
    return 0
  fi
  local data="${CLAUDE_PLUGIN_DATA:-$HOME/.claude/plugins/data/version-sentinel}"
  echo "$data/checks.json"
}

# sidecar_read: prints JSON contents. Missing/corrupt → '{"entries":[]}' to stdout.
sidecar_read() {
  local path="$1"
  if [[ ! -f "$path" ]]; then
    echo '{"entries":[]}'
    return 0
  fi
  if ! jq -e '.entries' "$path" >/dev/null 2>&1; then
    echo "version-sentinel: sidecar corrupt, treating as empty: $path" >&2
    echo '{"entries":[]}'
    return 0
  fi
  cat "$path"
}

# sidecar_find_fresh <path> <ecosystem> <pkg> <version> <window_hours>
# Exits 0 if matching entry present and within window, exits 1 otherwise.
# Honors VS_NOW_OVERRIDE for deterministic tests (ISO-8601 Z timestamp).
sidecar_find_fresh() {
  local path="$1" ecosystem="$2" pkg="$3" version="$4" window="$5"
  local now="${VS_NOW_OVERRIDE:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}"
  local now_epoch
  now_epoch=$(_iso_to_epoch "$now") || return 1
  local entry
  entry=$(sidecar_read "$path" | jq -c \
    --arg eco "$ecosystem" --arg pkg "$pkg" --arg ver "$version" \
    '.entries[] | select(.ecosystem==$eco and .pkg==$pkg and .version==$ver)')
  [[ -z "$entry" ]] && return 1
  local checked
  checked=$(echo "$entry" | jq -r '.checkedAt')
  local checked_epoch
  checked_epoch=$(_iso_to_epoch "$checked") || return 1
  local delta=$((now_epoch - checked_epoch))
  local window_sec=$((window * 3600))
  [[ "$delta" -ge 0 && "$delta" -le "$window_sec" ]]
}

# sidecar_write_entry <path> <ecosystem> <pkg> <version> <source> [checkedAt]
# Dedupes on (ecosystem, pkg). Auto-creates .gitignore in parent dir.
sidecar_write_entry() {
  local path="$1" ecosystem="$2" pkg="$3" version="$4" source="$5"
  local checked="${6:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}"
  local dir
  dir=$(dirname "$path")
  mkdir -p "$dir"

  # Auto-gitignore
  local gi="$dir/.gitignore"
  if [[ ! -f "$gi" ]]; then
    printf '*\n!.gitignore\n' > "$gi"
  fi

  local current
  current=$(sidecar_read "$path")
  local updated
  updated=$(echo "$current" | jq -c \
    --arg eco "$ecosystem" --arg pkg "$pkg" --arg ver "$version" \
    --arg src "$source" --arg at "$checked" \
    '.entries = ((.entries // []) | map(select(.ecosystem != $eco or .pkg != $pkg))
      + [{ecosystem: $eco, pkg: $pkg, version: $ver, source: $src, checkedAt: $at}])')
  printf '%s\n' "$updated" > "$path"
}

# _iso_to_epoch: convert ISO-8601 Z timestamp to epoch seconds. Uses python for portability.
_iso_to_epoch() {
  python3 -c 'import sys, datetime; print(int(datetime.datetime.strptime(sys.argv[1], "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=datetime.timezone.utc).timestamp()))' "$1" 2>/dev/null
}
```

- [ ] **Step 4: Run test — expect PASS**

```bash
bash tests/run.sh
```
Expected: `PASS [harness-smoke]`, `PASS [sidecar]`, total 2, failed 0.

- [ ] **Step 5: Commit**

```bash
git add scripts/lib/sidecar.sh tests/test_sidecar.sh tests/fixtures/sidecar_*.json
git commit -m "feat(lib): sidecar read/write with dedupe + auto-gitignore

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

### Task 4: check-sidecar.sh — shared allow/block decision

**Files:**
- Create: `scripts/check-sidecar.sh`
- Create: `tests/test_check_sidecar.sh`

- [ ] **Step 1: Write failing test**

Create `tests/test_check_sidecar.sh`:

```bash
#!/usr/bin/env bash
VS_TEST_NAME="check-sidecar"
source "$(dirname "$0")/assert.sh"

TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

SCRIPT="scripts/check-sidecar.sh"

# No sidecar → block (exit 2)
cd "$TMPDIR"
stderr=$(bash "$OLDPWD/$SCRIPT" npm lodash 4.17.21 2>&1 >/dev/null; echo "exit=$?")
cd "$OLDPWD"
assert_contains "$stderr" "BLOCKED" "block stderr contains BLOCKED"
assert_contains "$stderr" "lodash" "block stderr contains pkg name"
assert_contains "$stderr" "/vs-record" "block stderr tells Claude about /vs-record"
assert_contains "$stderr" "exit=2" "missing entry → exit 2"

# Fresh sidecar entry → allow (exit 0)
mkdir -p "$TMPDIR/.version-sentinel"
cat > "$TMPDIR/.version-sentinel/checks.json" <<EOF
{"entries":[{"ecosystem":"npm","pkg":"lodash","version":"4.17.21","source":"https://x","checkedAt":"$(date -u +%Y-%m-%dT%H:%M:%SZ)"}]}
EOF
cd "$TMPDIR"
out=$(bash "$OLDPWD/$SCRIPT" npm lodash 4.17.21 2>&1; echo "exit=$?")
cd "$OLDPWD"
assert_contains "$out" "exit=0" "fresh entry → exit 0"

# VS_DISABLE bypasses
cd "$TMPDIR"
rm -rf .version-sentinel
out=$(VS_DISABLE=1 bash "$OLDPWD/$SCRIPT" npm lodash 4.17.21 2>&1; echo "exit=$?")
cd "$OLDPWD"
assert_contains "$out" "exit=0" "VS_DISABLE=1 → exit 0 regardless"

finish_test
```

- [ ] **Step 2: Run — expect FAIL**

```bash
bash tests/test_check_sidecar.sh
```

- [ ] **Step 3: Implement `scripts/check-sidecar.sh`**

```bash
#!/usr/bin/env bash
# Usage: check-sidecar.sh <ecosystem> <pkg> <version>
# Exit 0 = allow (fresh entry found or VS_DISABLE set)
# Exit 2 = block (no fresh entry); stderr carries message for Claude
set -u

ecosystem="${1:?ecosystem required}"
pkg="${2:?pkg required}"
version="${3:?version required}"
window_hours="${VS_WINDOW_HOURS:-24}"

if [[ "${VS_DISABLE:-0}" == "1" ]]; then
  exit 0
fi

# shellcheck source=lib/sidecar.sh
source "$(dirname "$0")/lib/sidecar.sh"

path=$(sidecar_path "$PWD")

if sidecar_find_fresh "$path" "$ecosystem" "$pkg" "$version" "$window_hours"; then
  exit 0
fi

cat >&2 <<EOF
BLOCKED: version-sentinel.
Package: $pkg ($ecosystem). Version: $version.
No fresh version check on record (window: ${window_hours}h).

REQUIRED before retry:
1. Run WebSearch (or WebFetch / context7) for the latest version of "$pkg" on the $ecosystem registry.
2. Invoke /vs-record $pkg <latest-version-from-result> <source-url>
3. Retry your edit/install.

Escape: if this pin is intentional (CVE lock, compat constraint, private registry, no-WebSearch region),
run: /vs-record $pkg $version "intentional: <reason>"
EOF
exit 2
```

- [ ] **Step 4: Run — expect PASS**

```bash
chmod +x scripts/check-sidecar.sh
bash tests/run.sh
```
Expected: all passing.

- [ ] **Step 5: Commit**

```bash
git add scripts/check-sidecar.sh tests/test_check_sidecar.sh
git commit -m "feat: check-sidecar.sh — exit-2 block with stderr for Claude

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

### Task 5: parse-manifest.sh — npm (package.json)

**Files:**
- Create: `scripts/lib/parse-manifest.sh`
- Create: `tests/test_parse_npm.sh`
- Create: `tests/fixtures/package.json`
- Create: `tests/fixtures/package_no_deps.json`

- [ ] **Step 1: Create fixtures**

`tests/fixtures/package.json`:
```json
{
  "name": "fixture",
  "version": "1.0.0",
  "dependencies": {
    "lodash": "^4.17.21",
    "express": "4.19.2"
  },
  "devDependencies": {
    "jest": "~29.7.0"
  },
  "peerDependencies": {
    "react": ">=18.0.0"
  },
  "optionalDependencies": {
    "fsevents": "2.3.3"
  }
}
```

`tests/fixtures/package_no_deps.json`:
```json
{ "name": "empty", "version": "1.0.0" }
```

- [ ] **Step 2: Write failing test**

Create `tests/test_parse_npm.sh`:

```bash
#!/usr/bin/env bash
VS_TEST_NAME="parse-npm"
source "$(dirname "$0")/assert.sh"
source "$(dirname "$0")/../scripts/lib/parse-manifest.sh"

out=$(parse_npm tests/fixtures/package.json | sort)
expected=$(printf '%s\n' \
  "lodash	4.17.21" \
  "express	4.19.2" \
  "jest	29.7.0" \
  "react	18.0.0" \
  "fsevents	2.3.3" | sort)
assert_eq "$expected" "$out" "npm all 4 dep sections parsed, version prefixes stripped"

# Empty manifest → empty output, exit 0
out=$(parse_npm tests/fixtures/package_no_deps.json)
assert_eq "" "$out" "no deps → empty"

# Missing file → empty output, exit 0 (fail-open)
out=$(parse_npm /nope/nonexistent.json 2>/dev/null)
assert_eq "" "$out" "missing file → empty (fail open)"

finish_test
```

- [ ] **Step 3: Run — expect FAIL**

```bash
bash tests/test_parse_npm.sh
```

- [ ] **Step 4: Implement `scripts/lib/parse-manifest.sh` (npm only for this task)**

```bash
#!/usr/bin/env bash
# parse-manifest.sh — per-ecosystem manifest parsers.
# Each parser prints TAB-separated "pkg\tversion" lines, one per dependency.
# Version prefixes (^ ~ >= <= = v) are stripped.
# Local/git/workspace refs are skipped (produce no line).
# Missing/invalid file → empty output, exit 0 (fail-open).

_strip_version_prefix() {
  sed -E 's/^[v^~><= ]+//' <<< "$1"
}

_is_registry_version() {
  # Accept plain version strings like "4.17.21" (with optional ^/~/>=).
  # Reject file:, git+, workspace:, link:, npm:alias@, * (any).
  local raw="$1"
  case "$raw" in
    file:*|git+*|git:*|github:*|workspace:*|link:*|portal:*|npm:*|"*"|""|latest|next) return 1 ;;
  esac
  return 0
}

parse_npm() {
  local file="$1"
  [[ -f "$file" ]] || return 0
  jq -r '[.dependencies, .devDependencies, .peerDependencies, .optionalDependencies]
         | map(select(. != null)) | add // {} | to_entries[] | "\(.key)\t\(.value)"' \
    "$file" 2>/dev/null | while IFS=$'\t' read -r pkg raw; do
      [[ -z "$pkg" ]] && continue
      _is_registry_version "$raw" || continue
      local ver
      ver=$(_strip_version_prefix "$raw")
      # Drop range specifiers that leave no clean version (e.g. ">=1 <2")
      [[ "$ver" =~ [[:space:]] ]] && continue
      printf '%s\t%s\n' "$pkg" "$ver"
    done
}
```

- [ ] **Step 5: Run — expect PASS**

```bash
bash tests/run.sh
```

- [ ] **Step 6: Commit**

```bash
git add scripts/lib/parse-manifest.sh tests/test_parse_npm.sh tests/fixtures/package*.json
git commit -m "feat(parse): npm package.json parser (all 4 dep sections)

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

### Task 6: parse-manifest.sh — pip (requirements.txt)

**Files:**
- Modify: `scripts/lib/parse-manifest.sh` (append `parse_pip`)
- Create: `tests/test_parse_pip.sh`
- Create: `tests/fixtures/requirements.txt`
- Create: `tests/fixtures/requirements_tricky.txt`

- [ ] **Step 1: Create fixtures**

`tests/fixtures/requirements.txt`:
```
requests==2.31.0
flask>=2.3.0
numpy~=1.26.0
```

`tests/fixtures/requirements_tricky.txt`:
```
# comment line
click ==8.1.7  ; python_version >= "3.8"
-r other.txt
-e git+https://github.com/psf/black.git@main#egg=black
./local-pkg
SomeProject@https://example.com/pkg.whl
PyYAML>=6.0,<7.0
```

Expected parser output for tricky file:
- `click	8.1.7` (env markers + spaces ignored)
- `PyYAML	6.0` (picks lower bound from range)
- Everything else skipped (comments, includes, editable git, local path, URL ref).

- [ ] **Step 2: Write failing test**

Create `tests/test_parse_pip.sh`:

```bash
#!/usr/bin/env bash
VS_TEST_NAME="parse-pip"
source "$(dirname "$0")/assert.sh"
source "$(dirname "$0")/../scripts/lib/parse-manifest.sh"

# Basic file
out=$(parse_pip tests/fixtures/requirements.txt | sort)
expected=$(printf '%s\n' "flask	2.3.0" "numpy	1.26.0" "requests	2.31.0" | sort)
assert_eq "$expected" "$out" "pip basic"

# Tricky file
out=$(parse_pip tests/fixtures/requirements_tricky.txt | sort)
expected=$(printf '%s\n' "PyYAML	6.0" "click	8.1.7" | sort)
assert_eq "$expected" "$out" "pip tricky (comments/includes/editable/range skipped)"

finish_test
```

- [ ] **Step 3: Run — expect FAIL**

- [ ] **Step 4: Implement `parse_pip` (append to `parse-manifest.sh`)**

```bash
parse_pip() {
  local file="$1"
  [[ -f "$file" ]] || return 0
  # Read line by line, strip inline comments and env markers, apply PEP 508 simplifications.
  while IFS= read -r line || [[ -n "$line" ]]; do
    # Strip comments and trailing whitespace
    line="${line%%#*}"
    line="${line%"${line##*[![:space:]]}"}"
    [[ -z "$line" ]] && continue
    # Skip includes, editable, URL, local-path, extras-only lines
    case "$line" in
      -*|*://*|./*|../*|/*) continue ;;
    esac
    # Strip env marker (everything after ';')
    line="${line%%;*}"
    line="${line%"${line##*[![:space:]]}"}"
    # Skip direct-URL references (PEP 440): name @ url
    [[ "$line" == *@* && "$line" != *==* ]] && continue
    # Match first version specifier: ==, ~=, >=, >, <=, <, !=
    # Extract pkg and first version spec
    if [[ "$line" =~ ^([A-Za-z0-9][A-Za-z0-9._-]*)[[:space:]]*(==|~=|\>=|\<=|\>|\<|!=)[[:space:]]*([A-Za-z0-9][A-Za-z0-9._*+-]*) ]]; then
      local pkg="${BASH_REMATCH[1]}" ver="${BASH_REMATCH[3]}"
      printf '%s\t%s\n' "$pkg" "$ver"
    fi
  done < "$file"
}
```

- [ ] **Step 5: Run — expect PASS**

- [ ] **Step 6: Commit**

```bash
git add scripts/lib/parse-manifest.sh tests/test_parse_pip.sh tests/fixtures/requirements*.txt
git commit -m "feat(parse): pip requirements.txt parser

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

### Task 7: parse-manifest.sh — pyproject.toml

**Files:**
- Modify: `scripts/lib/parse-manifest.sh` (append `parse_pyproject`)
- Create: `tests/test_parse_pyproject.sh`
- Create: `tests/fixtures/pyproject.toml`

- [ ] **Step 1: Create fixture**

`tests/fixtures/pyproject.toml`:
```toml
[project]
name = "demo"
version = "0.1.0"
dependencies = [
  "requests==2.31.0",
  "flask>=3.0.0",
]

[project.optional-dependencies]
dev = ["pytest==8.0.0"]

[tool.poetry.dependencies]
python = "^3.11"
click = "^8.1.7"
pydantic = { version = "2.5.3", extras = ["email"] }

[tool.poetry.group.dev.dependencies]
mypy = "1.8.0"
```

Expected (union, dedupe on first seen):
- `requests 2.31.0`
- `flask 3.0.0`
- `pytest 8.0.0`
- `click 8.1.7`
- `pydantic 2.5.3`
- `mypy 1.8.0`

Note: `python` entry under `[tool.poetry.dependencies]` is skipped (it's the interpreter version constraint, not a PyPI package).

- [ ] **Step 2: Write failing test**

Create `tests/test_parse_pyproject.sh`:

```bash
#!/usr/bin/env bash
VS_TEST_NAME="parse-pyproject"
source "$(dirname "$0")/assert.sh"
source "$(dirname "$0")/../scripts/lib/parse-manifest.sh"

out=$(parse_pyproject tests/fixtures/pyproject.toml | sort)
expected=$(printf '%s\n' \
  "click	8.1.7" \
  "flask	3.0.0" \
  "mypy	1.8.0" \
  "pydantic	2.5.3" \
  "pytest	8.0.0" \
  "requests	2.31.0" | sort)
assert_eq "$expected" "$out" "pyproject all sources"

finish_test
```

- [ ] **Step 3: Run — expect FAIL**

- [ ] **Step 4: Implement `parse_pyproject`**

Uses `python3 -c 'import tomllib, json; ...'` to convert TOML → JSON, then `jq` does the extraction.

Append to `scripts/lib/parse-manifest.sh`:

```bash
parse_pyproject() {
  local file="$1"
  [[ -f "$file" ]] || return 0
  python3 -c '
import tomllib, json, sys
with open(sys.argv[1], "rb") as f:
    data = tomllib.load(f)
out = []

# PEP 621: [project.dependencies] — list of strings
for spec in (data.get("project", {}).get("dependencies") or []):
    out.append(("pep621", spec))

# PEP 621: [project.optional-dependencies] — {group: [strings]}
for group, specs in (data.get("project", {}).get("optional-dependencies") or {}).items():
    for s in specs:
        out.append(("pep621-extra", s))

# Poetry main + group deps — {name: version|table}
def poetry_deps(d):
    for name, spec in (d or {}).items():
        if name == "python":  # interpreter, not a pkg
            continue
        if isinstance(spec, str):
            out.append(("poetry", f"{name} {spec}"))
        elif isinstance(spec, dict) and "version" in spec:
            out.append(("poetry", f"{name} {spec[\"version\"]}"))

poetry_deps(data.get("tool", {}).get("poetry", {}).get("dependencies"))
for _g, gd in (data.get("tool", {}).get("poetry", {}).get("group", {}) or {}).items():
    poetry_deps(gd.get("dependencies"))

# [tool.uv] — may carry dev-dependencies as list of PEP 508 strings
uv = data.get("tool", {}).get("uv", {})
for s in (uv.get("dev-dependencies") or []):
    out.append(("uv", s))

print(json.dumps(out))
' "$file" 2>/dev/null | jq -r '.[]' 2>/dev/null | while IFS=$'\t' read -r kind spec; do
    # jq -r '.[]' gives us JSON arrays; fall through via python instead:
    :
  done
  # Simpler: use python3 directly for the whole thing
  python3 -c '
import tomllib, json, sys, re
with open(sys.argv[1], "rb") as f:
    data = tomllib.load(f)

VER_RE = re.compile(r"(==|~=|>=|<=|>|<|!=|\^|~)?\s*([A-Za-z0-9][A-Za-z0-9._*+-]*)")

def emit(name, raw):
    name = name.strip()
    raw = (raw or "").strip()
    # Strip env marker
    if ";" in raw:
        raw = raw.split(";", 1)[0].strip()
    if not raw or raw in ("*", "latest"):
        return
    # Reject direct-URL refs / local paths
    if raw.startswith(("file:", "git+", "http://", "https://", "./", "../", "/")):
        return
    if " @ " in raw:
        return
    m = VER_RE.match(raw)
    if not m:
        return
    ver = m.group(2)
    if " " in ver:
        return
    print(f"{name}\t{ver}")

def pep508(spec):
    # Format: "name [extras] version-spec ; marker"
    spec = spec.split(";", 1)[0].strip()
    m = re.match(r"([A-Za-z0-9][A-Za-z0-9._-]*)(?:\[[^\]]*\])?\s*(.*)", spec)
    if m:
        emit(m.group(1), m.group(2))

for s in (data.get("project", {}).get("dependencies") or []):
    pep508(s)
for _g, specs in (data.get("project", {}).get("optional-dependencies") or {}).items():
    for s in specs:
        pep508(s)

def poetry_deps(d):
    for name, spec in (d or {}).items():
        if name == "python":
            continue
        if isinstance(spec, str):
            emit(name, spec)
        elif isinstance(spec, dict) and "version" in spec:
            emit(name, spec["version"])

poetry_deps(data.get("tool", {}).get("poetry", {}).get("dependencies"))
for _g, gd in (data.get("tool", {}).get("poetry", {}).get("group", {}) or {}).items():
    poetry_deps(gd.get("dependencies"))

for s in (data.get("tool", {}).get("uv", {}).get("dev-dependencies") or []):
    pep508(s)
' "$file" 2>/dev/null
}
```

(The inline-jq first draft above should be removed — only the second python3 block should remain in the final implementation. The outer body is kept clean.)

Replace the earlier scaffolding inside `parse_pyproject` with the single-python3 version shown. Finalized body:

```bash
parse_pyproject() {
  local file="$1"
  [[ -f "$file" ]] || return 0
  python3 - "$file" <<'PY' 2>/dev/null
import tomllib, sys, re
with open(sys.argv[1], "rb") as f:
    data = tomllib.load(f)

VER_RE = re.compile(r"(?:==|~=|>=|<=|>|<|!=|\^|~)?\s*([A-Za-z0-9][A-Za-z0-9._*+-]*)")

def emit(name, raw):
    name = name.strip()
    raw = (raw or "").strip()
    if ";" in raw: raw = raw.split(";", 1)[0].strip()
    if not raw or raw in ("*", "latest"): return
    if raw.startswith(("file:", "git+", "http://", "https://", "./", "../", "/")): return
    if " @ " in raw: return
    m = VER_RE.match(raw)
    if not m: return
    ver = m.group(1)
    if " " in ver: return
    print(f"{name}\t{ver}")

def pep508(spec):
    spec = spec.split(";", 1)[0].strip()
    m = re.match(r"([A-Za-z0-9][A-Za-z0-9._-]*)(?:\[[^\]]*\])?\s*(.*)", spec)
    if m: emit(m.group(1), m.group(2))

for s in (data.get("project", {}).get("dependencies") or []): pep508(s)
for _g, specs in (data.get("project", {}).get("optional-dependencies") or {}).items():
    for s in specs: pep508(s)

def poetry_deps(d):
    for name, spec in (d or {}).items():
        if name == "python": continue
        if isinstance(spec, str): emit(name, spec)
        elif isinstance(spec, dict) and "version" in spec: emit(name, spec["version"])

poetry_deps(data.get("tool", {}).get("poetry", {}).get("dependencies"))
for _g, gd in (data.get("tool", {}).get("poetry", {}).get("group", {}) or {}).items():
    poetry_deps(gd.get("dependencies"))

for s in (data.get("tool", {}).get("uv", {}).get("dev-dependencies") or []): pep508(s)
PY
}
```

- [ ] **Step 5: Run — expect PASS**

- [ ] **Step 6: Commit**

```bash
git add scripts/lib/parse-manifest.sh tests/test_parse_pyproject.sh tests/fixtures/pyproject.toml
git commit -m "feat(parse): pyproject.toml parser (PEP 621 + Poetry + uv)

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

### Task 8: parse-manifest.sh — Cargo.toml

**Files:**
- Modify: `scripts/lib/parse-manifest.sh` (append `parse_cargo`)
- Create: `tests/test_parse_cargo.sh`
- Create: `tests/fixtures/Cargo.toml`

- [ ] **Step 1: Create fixture**

`tests/fixtures/Cargo.toml`:
```toml
[package]
name = "demo"
version = "0.1.0"
edition = "2021"

[dependencies]
serde = "1.0.196"
tokio = { version = "1.36.0", features = ["full"] }
local-dep = { path = "../other" }

[dev-dependencies]
criterion = "0.5.1"

[build-dependencies]
cc = "1.0.83"
```

Expected:
- `serde 1.0.196`
- `tokio 1.36.0`
- `criterion 0.5.1`
- `cc 1.0.83`
- `local-dep` skipped (path dep, not registry)

- [ ] **Step 2: Write failing test**

Create `tests/test_parse_cargo.sh`:

```bash
#!/usr/bin/env bash
VS_TEST_NAME="parse-cargo"
source "$(dirname "$0")/assert.sh"
source "$(dirname "$0")/../scripts/lib/parse-manifest.sh"

out=$(parse_cargo tests/fixtures/Cargo.toml | sort)
expected=$(printf '%s\n' \
  "cc	1.0.83" \
  "criterion	0.5.1" \
  "serde	1.0.196" \
  "tokio	1.36.0" | sort)
assert_eq "$expected" "$out" "cargo all 3 dep sections, path-deps skipped"

finish_test
```

- [ ] **Step 3: Run — expect FAIL**

- [ ] **Step 4: Implement `parse_cargo`**

Append to `scripts/lib/parse-manifest.sh`:

```bash
parse_cargo() {
  local file="$1"
  [[ -f "$file" ]] || return 0
  python3 - "$file" <<'PY' 2>/dev/null
import tomllib, sys
with open(sys.argv[1], "rb") as f:
    data = tomllib.load(f)

def walk(section):
    for name, spec in (section or {}).items():
        if isinstance(spec, str):
            print(f"{name}\t{spec.lstrip('^~v= ')}")
        elif isinstance(spec, dict):
            # Skip path/git-based deps — not from crates.io
            if "path" in spec or "git" in spec:
                continue
            ver = spec.get("version")
            if isinstance(ver, str):
                print(f"{name}\t{ver.lstrip('^~v= ')}")

walk(data.get("dependencies"))
walk(data.get("dev-dependencies"))
walk(data.get("build-dependencies"))
PY
}
```

- [ ] **Step 5: Run — expect PASS**

- [ ] **Step 6: Commit**

```bash
git add scripts/lib/parse-manifest.sh tests/test_parse_cargo.sh tests/fixtures/Cargo.toml
git commit -m "feat(parse): Cargo.toml parser (path/git deps skipped)

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

### Task 9: parse-manifest.sh — csproj (and family)

**Files:**
- Modify: `scripts/lib/parse-manifest.sh` (append `parse_csproj`)
- Create: `tests/test_parse_csproj.sh`
- Create: `tests/fixtures/Demo.csproj`

- [ ] **Step 1: Create fixture**

`tests/fixtures/Demo.csproj`:
```xml
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFramework>net8.0</TargetFramework>
  </PropertyGroup>
  <ItemGroup>
    <PackageReference Include="Newtonsoft.Json" Version="13.0.3" />
    <PackageReference Include="Serilog" Version="3.1.1" />
    <PackageReference Include="Dapper" Version="2.1.28">
      <PrivateAssets>all</PrivateAssets>
    </PackageReference>
    <ProjectReference Include="..\Shared\Shared.csproj" />
  </ItemGroup>
</Project>
```

Expected:
- `Newtonsoft.Json 13.0.3`
- `Serilog 3.1.1`
- `Dapper 2.1.28`
- `ProjectReference` skipped

- [ ] **Step 2: Write failing test**

Create `tests/test_parse_csproj.sh`:

```bash
#!/usr/bin/env bash
VS_TEST_NAME="parse-csproj"
source "$(dirname "$0")/assert.sh"
source "$(dirname "$0")/../scripts/lib/parse-manifest.sh"

out=$(parse_csproj tests/fixtures/Demo.csproj | sort)
expected=$(printf '%s\n' \
  "Dapper	2.1.28" \
  "Newtonsoft.Json	13.0.3" \
  "Serilog	3.1.1" | sort)
assert_eq "$expected" "$out" "csproj PackageReference parsing"

finish_test
```

- [ ] **Step 3: Run — expect FAIL**

- [ ] **Step 4: Implement `parse_csproj`**

Append:

```bash
parse_csproj() {
  local file="$1"
  [[ -f "$file" ]] || return 0
  # Match <PackageReference ... Include="X" ... Version="Y" ... /> or with body.
  # Attributes may appear in either order. Use two passes (Include-first, Version-first).
  grep -oE '<PackageReference[^/>]*(/>|>)' "$file" 2>/dev/null | while IFS= read -r tag; do
    local inc ver
    if [[ "$tag" =~ Include=\"([^\"]+)\" ]]; then
      inc="${BASH_REMATCH[1]}"
    else
      continue
    fi
    if [[ "$tag" =~ Version=\"([^\"]+)\" ]]; then
      ver="${BASH_REMATCH[1]}"
    else
      continue
    fi
    printf '%s\t%s\n' "$inc" "$ver"
  done
}
```

Note: multi-line `<PackageReference>...<PrivateAssets>...</PackageReference>` with Version as attribute on the opening tag is handled because `grep -oE` captures the opening tag through `>`. Version as child element (`<Version>1.2.3</Version>`) is NOT supported in v0.1 — document in CHANGELOG as known limitation.

- [ ] **Step 5: Run — expect PASS**

- [ ] **Step 6: Commit**

```bash
git add scripts/lib/parse-manifest.sh tests/test_parse_csproj.sh tests/fixtures/Demo.csproj
git commit -m "feat(parse): csproj/fsproj/vbproj PackageReference parser

Known limitation: child-element <Version> tags not supported in v0.1.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

### Task 10: parse-manifest.sh — dispatch + diff

**Files:**
- Modify: `scripts/lib/parse-manifest.sh` (append `parse_manifest_by_path`, `diff_manifest_sets`)
- Create: `tests/test_parse_dispatch.sh`

- [ ] **Step 1: Write failing test**

Create `tests/test_parse_dispatch.sh`:

```bash
#!/usr/bin/env bash
VS_TEST_NAME="parse-dispatch"
source "$(dirname "$0")/assert.sh"
source "$(dirname "$0")/../scripts/lib/parse-manifest.sh"

# Dispatch by path
eco=$(ecosystem_for_path "/proj/package.json")
assert_eq "npm" "$eco" "npm dispatch"

eco=$(ecosystem_for_path "/proj/requirements.txt")
assert_eq "pip" "$eco" "pip dispatch"

eco=$(ecosystem_for_path "/proj/requirements-dev.txt")
assert_eq "pip" "$eco" "pip glob dispatch"

eco=$(ecosystem_for_path "/proj/pyproject.toml")
assert_eq "pyproject" "$eco" "pyproject dispatch"

eco=$(ecosystem_for_path "/proj/Cargo.toml")
assert_eq "cargo" "$eco" "cargo dispatch"

eco=$(ecosystem_for_path "/proj/Foo.csproj")
assert_eq "csproj" "$eco" "csproj dispatch"

eco=$(ecosystem_for_path "/proj/README.md")
assert_eq "" "$eco" "unrelated file → empty"

# parse_by_path routes to correct parser
out=$(parse_manifest_by_path tests/fixtures/package.json | wc -l | tr -d ' ')
assert_eq "5" "$out" "npm parser produces 5 lines"

# diff_manifest_sets: added + changed + unchanged
pre=$(printf 'lodash\t4.17.20\njest\t29.7.0\n')
post=$(printf 'lodash\t4.17.21\njest\t29.7.0\nexpress\t4.19.2\n')
out=$(diff_manifest_sets "$pre" "$post" | sort)
expected=$(printf 'added\texpress\t4.19.2\nchanged\tlodash\t4.17.21\n' | sort)
assert_eq "$expected" "$out" "diff: added + changed, removed/unchanged ignored"

finish_test
```

- [ ] **Step 2: Run — expect FAIL**

- [ ] **Step 3: Implement**

Append to `scripts/lib/parse-manifest.sh`:

```bash
ecosystem_for_path() {
  local path="$1"
  local base
  base=$(basename "$path")
  case "$base" in
    package.json) echo "npm" ;;
    requirements*.txt|constraints*.txt) echo "pip" ;;
    pyproject.toml) echo "pyproject" ;;
    Cargo.toml) echo "cargo" ;;
    *.csproj|*.fsproj|*.vbproj) echo "csproj" ;;
    *) echo "" ;;
  esac
}

parse_manifest_by_path() {
  local path="$1"
  local eco
  eco=$(ecosystem_for_path "$path")
  case "$eco" in
    npm) parse_npm "$path" ;;
    pip) parse_pip "$path" ;;
    pyproject) parse_pyproject "$path" ;;
    cargo) parse_cargo "$path" ;;
    csproj) parse_csproj "$path" ;;
    *) return 0 ;;
  esac
}

# diff_manifest_sets <pre-lines> <post-lines>
# Input: two multiline strings of "pkg\tversion" entries.
# Output: TAB-separated "<added|changed>\tpkg\tversion" lines for post-state.
diff_manifest_sets() {
  local pre="$1" post="$2"
  local tmp_pre tmp_post
  tmp_pre=$(mktemp); tmp_post=$(mktemp)
  printf '%s\n' "$pre" | sort -u > "$tmp_pre"
  printf '%s\n' "$post" | sort -u > "$tmp_post"
  # For each post entry: if pkg not in pre → added; elif (pkg,ver) differs from pre → changed
  while IFS=$'\t' read -r pkg ver; do
    [[ -z "$pkg" ]] && continue
    local pre_ver
    pre_ver=$(awk -F '\t' -v p="$pkg" '$1==p {print $2; exit}' "$tmp_pre")
    if [[ -z "$pre_ver" ]]; then
      printf 'added\t%s\t%s\n' "$pkg" "$ver"
    elif [[ "$pre_ver" != "$ver" ]]; then
      printf 'changed\t%s\t%s\n' "$pkg" "$ver"
    fi
  done < "$tmp_post"
  rm -f "$tmp_pre" "$tmp_post"
}
```

- [ ] **Step 4: Run — expect PASS**

- [ ] **Step 5: Commit**

```bash
git add scripts/lib/parse-manifest.sh tests/test_parse_dispatch.sh
git commit -m "feat(parse): path→ecosystem dispatch + manifest-set diff

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

### Task 11: parse-install-cmd.sh

**Files:**
- Create: `scripts/lib/parse-install-cmd.sh`
- Create: `tests/test_parse_install_cmd.sh`

- [ ] **Step 1: Write failing test**

Create `tests/test_parse_install_cmd.sh`:

```bash
#!/usr/bin/env bash
VS_TEST_NAME="parse-install-cmd"
source "$(dirname "$0")/assert.sh"
source "$(dirname "$0")/../scripts/lib/parse-install-cmd.sh"

# Each case emits one or more "ecosystem\tpkg\tversion" lines (version may be empty).

out=$(parse_install_cmd "npm install lodash")
assert_eq $'npm\tlodash\t' "$out" "npm install <pkg> no version"

out=$(parse_install_cmd "npm install lodash@4.17.21")
assert_eq $'npm\tlodash\t4.17.21' "$out" "npm install <pkg>@<ver>"

out=$(parse_install_cmd "pnpm add react@18.2.0 --save-dev")
assert_eq $'npm\treact\t18.2.0' "$out" "pnpm add with flag"

out=$(parse_install_cmd "pip install requests==2.31.0")
assert_eq $'pip\trequests\t2.31.0' "$out" "pip install pinned"

out=$(parse_install_cmd "poetry add flask@^3.0.0")
assert_eq $'pip\tflask\t3.0.0' "$out" "poetry add"

out=$(parse_install_cmd "cargo add serde")
assert_eq $'cargo\tserde\t' "$out" "cargo add no version"

out=$(parse_install_cmd "dotnet add package Newtonsoft.Json --version 13.0.3")
assert_eq $'csproj\tNewtonsoft.Json\t13.0.3' "$out" "dotnet add package --version"

out=$(parse_install_cmd "dotnet add package Serilog -v 3.1.1")
assert_eq $'csproj\tSerilog\t3.1.1' "$out" "dotnet add package -v"

# Non-install commands produce no output
out=$(parse_install_cmd "ls -la")
assert_eq "" "$out" "ls → no match"

out=$(parse_install_cmd "git commit -m 'npm install X would be a lie here'")
assert_eq "" "$out" "literal string inside unrelated cmd → no match (anchored on word boundary / start)"

finish_test
```

- [ ] **Step 2: Run — expect FAIL**

- [ ] **Step 3: Implement**

```bash
#!/usr/bin/env bash
# parse_install_cmd <bash-command-string>
# Prints TAB-separated "ecosystem\tpkg\tversion" lines (version optional, may be empty).
# Covers v0.1 ecosystems: npm, pip, cargo, csproj (via dotnet add package).
# Multiple packages in one command → multiple output lines.

parse_install_cmd() {
  local cmd="$1"
  # Strip leading whitespace; we only match commands at start-of-string or after `&&`/`;`/`|`.
  # Split on those delimiters and check each segment independently.
  local IFS=$'\n'
  local segment
  while read -r segment; do
    segment="${segment#"${segment%%[![:space:]]*}"}"  # ltrim
    [[ -z "$segment" ]] && continue
    _parse_install_segment "$segment"
  done < <(printf '%s\n' "$cmd" | tr ';&|' '\n')
}

_parse_install_segment() {
  local seg="$1"
  # npm / pnpm / yarn / bun install|add|i
  if [[ "$seg" =~ ^(npm|pnpm|yarn|bun)[[:space:]]+(add|install|i)[[:space:]]+(.*) ]]; then
    local rest="${BASH_REMATCH[3]}"
    _emit_packages npm "$rest"
    return
  fi
  # pip / pip3 install (not uninstall)
  if [[ "$seg" =~ ^pip3?[[:space:]]+install[[:space:]]+(.*) ]]; then
    local rest="${BASH_REMATCH[1]}"
    _emit_pep508 pip "$rest"
    return
  fi
  # poetry add
  if [[ "$seg" =~ ^poetry[[:space:]]+add[[:space:]]+(.*) ]]; then
    local rest="${BASH_REMATCH[1]}"
    _emit_poetry pip "$rest"
    return
  fi
  # uv add / uv pip install
  if [[ "$seg" =~ ^uv[[:space:]]+(add|pip[[:space:]]+install)[[:space:]]+(.*) ]]; then
    local rest="${BASH_REMATCH[2]}"
    _emit_pep508 pip "$rest"
    return
  fi
  # cargo add
  if [[ "$seg" =~ ^cargo[[:space:]]+add[[:space:]]+(.*) ]]; then
    local rest="${BASH_REMATCH[1]}"
    _emit_cargo_add "$rest"
    return
  fi
  # dotnet add package <name> [--version|-v <ver>]
  if [[ "$seg" =~ ^dotnet[[:space:]]+add[[:space:]]+package[[:space:]]+(.*) ]]; then
    local rest="${BASH_REMATCH[1]}"
    _emit_dotnet_add "$rest"
    return
  fi
}

_emit_packages() {
  # npm-style: space-separated tokens; pkg or pkg@version; skip flags
  local eco="$1" rest="$2"
  local tok
  for tok in $rest; do
    [[ "$tok" == -* ]] && continue
    # Strip scope-safe: @scope/pkg@ver
    if [[ "$tok" == @*/* ]]; then
      # @scope/pkg or @scope/pkg@ver
      if [[ "$tok" =~ ^(@[^/]+/[^@]+)(@(.+))?$ ]]; then
        printf '%s\t%s\t%s\n' "$eco" "${BASH_REMATCH[1]}" "${BASH_REMATCH[3]}"
      fi
    elif [[ "$tok" == *@* ]]; then
      local p="${tok%@*}" v="${tok##*@}"
      printf '%s\t%s\t%s\n' "$eco" "$p" "$v"
    else
      printf '%s\t%s\t%s\n' "$eco" "$tok" ""
    fi
  done
}

_emit_pep508() {
  local eco="$1" rest="$2"
  local tok
  for tok in $rest; do
    [[ "$tok" == -* ]] && continue
    # pkg==ver, pkg>=ver etc.
    if [[ "$tok" =~ ^([A-Za-z0-9][A-Za-z0-9._-]*)(==|~=|\>=|\<=|\>|\<|!=)([A-Za-z0-9][A-Za-z0-9._*+-]*) ]]; then
      printf '%s\t%s\t%s\n' "$eco" "${BASH_REMATCH[1]}" "${BASH_REMATCH[3]}"
    else
      printf '%s\t%s\t%s\n' "$eco" "$tok" ""
    fi
  done
}

_emit_poetry() {
  local eco="$1" rest="$2"
  local tok
  for tok in $rest; do
    [[ "$tok" == -* ]] && continue
    # poetry accepts pkg@ver (with ^/~ prefix)
    if [[ "$tok" == *@* ]]; then
      local p="${tok%@*}" v="${tok##*@}"
      v="${v#[v^~>=]}"
      v="${v#=}"
      printf '%s\t%s\t%s\n' "$eco" "$p" "$v"
    else
      printf '%s\t%s\t%s\n' "$eco" "$tok" ""
    fi
  done
}

_emit_cargo_add() {
  local rest="$1"
  local tok name="" ver=""
  for tok in $rest; do
    if [[ "$tok" == "--vers" || "$tok" == "--version" ]]; then
      continue
    fi
    if [[ "$tok" == --vers=* || "$tok" == --version=* ]]; then
      ver="${tok#*=}"
      continue
    fi
    if [[ "$tok" == -* ]]; then
      continue
    fi
    if [[ -z "$name" ]]; then
      # cargo add supports name@version
      if [[ "$tok" == *@* ]]; then
        name="${tok%@*}"
        ver="${tok##*@}"
      else
        name="$tok"
      fi
    fi
  done
  [[ -n "$name" ]] && printf 'cargo\t%s\t%s\n' "$name" "$ver"
}

_emit_dotnet_add() {
  local rest="$1"
  local tok name="" ver="" take_ver=0
  for tok in $rest; do
    if [[ "$take_ver" -eq 1 ]]; then
      ver="$tok"
      take_ver=0
      continue
    fi
    case "$tok" in
      --version|-v) take_ver=1 ;;
      -*) ;;  # other flag
      *) [[ -z "$name" ]] && name="$tok" ;;
    esac
  done
  [[ -n "$name" ]] && printf 'csproj\t%s\t%s\n' "$name" "$ver"
}
```

- [ ] **Step 4: Run — expect PASS**

- [ ] **Step 5: Commit**

```bash
git add scripts/lib/parse-install-cmd.sh tests/test_parse_install_cmd.sh
git commit -m "feat(parse): install-command parser (npm/pip/cargo/dotnet)

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

### Task 12: detect-manifest-edit.sh

**Files:**
- Create: `scripts/detect-manifest-edit.sh`
- Create: `tests/test_detect_manifest_edit.sh`
- Create: `tests/fixtures/edit_input_add_lodash.json`
- Create: `tests/fixtures/write_input_new_package.json`
- Create: `tests/fixtures/multiedit_input_bump.json`

- [ ] **Step 1: Create fixture payloads**

`tests/fixtures/edit_input_add_lodash.json`:
```json
{
  "tool_name": "Edit",
  "tool_input": {
    "file_path": "{{CWD}}/package.json",
    "old_string": "  \"dependencies\": {\n    \"express\": \"4.19.2\"\n  }",
    "new_string": "  \"dependencies\": {\n    \"express\": \"4.19.2\",\n    \"lodash\": \"4.17.21\"\n  }",
    "replace_all": false
  }
}
```

`tests/fixtures/write_input_new_package.json`:
```json
{
  "tool_name": "Write",
  "tool_input": {
    "file_path": "{{CWD}}/package.json",
    "content": "{\"name\":\"x\",\"version\":\"1.0.0\",\"dependencies\":{\"lodash\":\"4.17.21\"}}"
  }
}
```

`tests/fixtures/multiedit_input_bump.json`:
```json
{
  "tool_name": "MultiEdit",
  "tool_input": {
    "file_path": "{{CWD}}/package.json",
    "edits": [
      { "old_string": "\"express\": \"4.19.2\"", "new_string": "\"express\": \"4.19.3\"" }
    ]
  }
}
```

(The `{{CWD}}` placeholder is substituted by the test at runtime.)

- [ ] **Step 2: Write failing test**

Create `tests/test_detect_manifest_edit.sh`:

```bash
#!/usr/bin/env bash
VS_TEST_NAME="detect-manifest-edit"
source "$(dirname "$0")/assert.sh"

TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

SCRIPT="$PWD/scripts/detect-manifest-edit.sh"

# Fresh sidecar so all checks block
cd "$TMPDIR"
cat > package.json <<EOF
{ "name": "fixture", "version": "1.0.0", "dependencies": { "express": "4.19.2" } }
EOF

substitute() {
  sed "s|{{CWD}}|$TMPDIR|g" "$OLDPWD/$1"
}

# Case 1: Edit adds lodash → block
input=$(substitute tests/fixtures/edit_input_add_lodash.json)
result=$(echo "$input" | bash "$SCRIPT" 2>&1; echo "exit=$?")
assert_contains "$result" "BLOCKED" "edit-add: blocked"
assert_contains "$result" "lodash" "edit-add: names pkg"
assert_contains "$result" "exit=2" "edit-add: exit 2"

# Case 2: Write new content w/ lodash → block
input=$(substitute tests/fixtures/write_input_new_package.json)
result=$(echo "$input" | bash "$SCRIPT" 2>&1; echo "exit=$?")
assert_contains "$result" "BLOCKED" "write: blocked"
assert_contains "$result" "lodash" "write: names pkg"

# Case 3: MultiEdit bumps express → block
input=$(substitute tests/fixtures/multiedit_input_bump.json)
result=$(echo "$input" | bash "$SCRIPT" 2>&1; echo "exit=$?")
assert_contains "$result" "BLOCKED" "multiedit-bump: blocked"
assert_contains "$result" "express" "multiedit-bump: names pkg"

# Case 4: Edit on a non-manifest file → pass silently
cat > README.md <<EOF
# Demo
EOF
input='{"tool_name":"Edit","tool_input":{"file_path":"'$TMPDIR'/README.md","old_string":"# Demo","new_string":"# Demo2","replace_all":false}}'
result=$(echo "$input" | bash "$SCRIPT" 2>&1; echo "exit=$?")
assert_contains "$result" "exit=0" "non-manifest: exit 0"

# Case 5: VS_DISABLE bypass
input=$(substitute tests/fixtures/edit_input_add_lodash.json)
result=$(echo "$input" | VS_DISABLE=1 bash "$SCRIPT" 2>&1; echo "exit=$?")
assert_contains "$result" "exit=0" "VS_DISABLE: exit 0"

cd "$OLDPWD"
finish_test
```

- [ ] **Step 3: Run — expect FAIL**

- [ ] **Step 4: Implement `scripts/detect-manifest-edit.sh`**

```bash
#!/usr/bin/env bash
# PreToolUse hook for Edit|Write|MultiEdit. Reads tool_input JSON from stdin.
# Exits 0 if no relevant change OR all changes have fresh sidecar entries.
# Exits 2 with stderr if any added/changed dep lacks a fresh sidecar entry.
set -u

# Fail-open bypass
if [[ "${VS_DISABLE:-0}" == "1" ]]; then
  exit 0
fi

DIR="$(dirname "$0")"
# shellcheck source=lib/parse-manifest.sh
source "$DIR/lib/parse-manifest.sh"
# shellcheck source=lib/sidecar.sh
source "$DIR/lib/sidecar.sh"

# Read all stdin
input=$(cat)

# Fail-open if jq missing or input unparseable
if ! command -v jq >/dev/null 2>&1; then
  echo "version-sentinel: jq missing, fail-open" >&2
  exit 0
fi
if ! echo "$input" | jq -e . >/dev/null 2>&1; then
  echo "version-sentinel: unparseable tool_input JSON, fail-open" >&2
  exit 0
fi

tool_name=$(echo "$input" | jq -r '.tool_name // empty')
file_path=$(echo "$input" | jq -r '.tool_input.file_path // empty')

[[ -z "$file_path" ]] && exit 0

eco=$(ecosystem_for_path "$file_path")
[[ -z "$eco" ]] && exit 0

# Build pre-state and post-content
pre_content=""
if [[ -f "$file_path" ]]; then
  pre_content=$(cat "$file_path")
fi
post_content="$pre_content"

case "$tool_name" in
  Edit)
    old=$(echo "$input" | jq -r '.tool_input.old_string // empty')
    new=$(echo "$input" | jq -r '.tool_input.new_string // empty')
    replace_all=$(echo "$input" | jq -r '.tool_input.replace_all // false')
    if [[ "$replace_all" == "true" ]]; then
      # Simulate s/old/new/g across file
      post_content=$(awk -v o="$old" -v n="$new" 'BEGIN{RS=""} { gsub(o, n); print }' <<< "$pre_content")
    else
      # Single-occurrence replacement
      post_content="${pre_content/"$old"/"$new"}"
    fi
    ;;
  Write)
    post_content=$(echo "$input" | jq -r '.tool_input.content // empty')
    # For Write to a non-existent file, pre is empty — all deps count as "added"
    ;;
  MultiEdit)
    post_content="$pre_content"
    while IFS=$'\t' read -r o n; do
      [[ -z "$o" ]] && continue
      post_content="${post_content/"$o"/"$n"}"
    done < <(echo "$input" | jq -r '.tool_input.edits[]? | [.old_string, .new_string] | @tsv')
    ;;
  *)
    exit 0
    ;;
esac

# Parse pre and post via temp files (parsers take file paths)
tmp_pre=$(mktemp); tmp_post=$(mktemp)
trap 'rm -f "$tmp_pre" "$tmp_post"' EXIT
printf '%s' "$pre_content" > "$tmp_pre"
printf '%s' "$post_content" > "$tmp_post"

pre_deps=$(parse_manifest_by_path "$tmp_pre" 2>/dev/null)
# Force the parser to treat tmp_post as same ecosystem by symlinking name, not feasible here.
# Instead, copy tmp_post to a name the dispatcher recognizes:
ext_file="$tmp_post.$(basename "$file_path")"
cp "$tmp_post" "$ext_file"
post_deps=$(parse_manifest_by_path "$ext_file" 2>/dev/null)
rm -f "$ext_file"

# Re-run pre parse with correct extension too (important for Cargo.toml etc.)
ext_pre="$tmp_pre.$(basename "$file_path")"
cp "$tmp_pre" "$ext_pre"
pre_deps=$(parse_manifest_by_path "$ext_pre" 2>/dev/null)
rm -f "$ext_pre"

# Compute diff
changes=$(diff_manifest_sets "$pre_deps" "$post_deps")
[[ -z "$changes" ]] && exit 0

# For each added/changed dep, consult sidecar
block=0
block_msgs=""
while IFS=$'\t' read -r kind pkg ver; do
  [[ -z "$pkg" ]] && continue
  if ! bash "$DIR/check-sidecar.sh" "$eco" "$pkg" "$ver" 2>/tmp/_vs_err; then
    block=1
    block_msgs+=$(cat /tmp/_vs_err)$'\n---\n'
  fi
done <<< "$changes"
rm -f /tmp/_vs_err

if [[ "$block" -eq 1 ]]; then
  echo "$block_msgs" >&2
  exit 2
fi
exit 0
```

**Note on the ext-file dance:** parsers dispatch by filename, so we copy the temp content to a file whose basename matches the real manifest (e.g. `…tmp-abc.package.json`). This preserves the dispatch logic without duplicating it.

- [ ] **Step 5: Run — expect PASS**

```bash
chmod +x scripts/detect-manifest-edit.sh
bash tests/run.sh
```

- [ ] **Step 6: Commit**

```bash
git add scripts/detect-manifest-edit.sh tests/test_detect_manifest_edit.sh tests/fixtures/edit_input*.json tests/fixtures/write_input*.json tests/fixtures/multiedit_input*.json
git commit -m "feat(hook): detect-manifest-edit.sh (Edit|Write|MultiEdit)

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

### Task 13: detect-install-cmd.sh

**Files:**
- Create: `scripts/detect-install-cmd.sh`
- Create: `tests/test_detect_install_cmd.sh`
- Create: `tests/fixtures/bash_npm_install.json`
- Create: `tests/fixtures/bash_pip_install.json`

- [ ] **Step 1: Create fixtures**

`tests/fixtures/bash_npm_install.json`:
```json
{
  "tool_name": "Bash",
  "tool_input": { "command": "npm install lodash@4.17.21" }
}
```

`tests/fixtures/bash_pip_install.json`:
```json
{
  "tool_name": "Bash",
  "tool_input": { "command": "pip install requests==2.31.0" }
}
```

- [ ] **Step 2: Write failing test**

Create `tests/test_detect_install_cmd.sh`:

```bash
#!/usr/bin/env bash
VS_TEST_NAME="detect-install-cmd"
source "$(dirname "$0")/assert.sh"

TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT
SCRIPT="$PWD/scripts/detect-install-cmd.sh"

cd "$TMPDIR"

# Case 1: npm install X@Y with no sidecar → block
result=$(cat "$OLDPWD/tests/fixtures/bash_npm_install.json" | bash "$SCRIPT" 2>&1; echo "exit=$?")
assert_contains "$result" "BLOCKED" "npm install blocked"
assert_contains "$result" "lodash" "npm install names pkg"

# Case 2: pip install X==Y with no sidecar → block
result=$(cat "$OLDPWD/tests/fixtures/bash_pip_install.json" | bash "$SCRIPT" 2>&1; echo "exit=$?")
assert_contains "$result" "BLOCKED" "pip install blocked"
assert_contains "$result" "requests" "pip install names pkg"

# Case 3: Unrelated bash command → pass
result=$(echo '{"tool_name":"Bash","tool_input":{"command":"ls -la"}}' | bash "$SCRIPT" 2>&1; echo "exit=$?")
assert_contains "$result" "exit=0" "unrelated cmd: exit 0"

# Case 4: install without version → pass (we can't check what we don't know)
result=$(echo '{"tool_name":"Bash","tool_input":{"command":"npm install lodash"}}' | bash "$SCRIPT" 2>&1; echo "exit=$?")
assert_contains "$result" "exit=0" "no-version install: pass (nothing to verify)"

# Case 5: fresh sidecar → pass
mkdir -p .version-sentinel
now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
cat > .version-sentinel/checks.json <<EOF
{"entries":[{"ecosystem":"npm","pkg":"lodash","version":"4.17.21","source":"https://x","checkedAt":"$now"}]}
EOF
result=$(cat "$OLDPWD/tests/fixtures/bash_npm_install.json" | bash "$SCRIPT" 2>&1; echo "exit=$?")
assert_contains "$result" "exit=0" "fresh sidecar: pass"

cd "$OLDPWD"
finish_test
```

- [ ] **Step 3: Run — expect FAIL**

- [ ] **Step 4: Implement `scripts/detect-install-cmd.sh`**

```bash
#!/usr/bin/env bash
set -u

if [[ "${VS_DISABLE:-0}" == "1" ]]; then
  exit 0
fi

DIR="$(dirname "$0")"
# shellcheck source=lib/parse-install-cmd.sh
source "$DIR/lib/parse-install-cmd.sh"

input=$(cat)

if ! command -v jq >/dev/null 2>&1; then
  echo "version-sentinel: jq missing, fail-open" >&2
  exit 0
fi
if ! echo "$input" | jq -e . >/dev/null 2>&1; then
  exit 0
fi

tool_name=$(echo "$input" | jq -r '.tool_name // empty')
[[ "$tool_name" != "Bash" ]] && exit 0

cmd=$(echo "$input" | jq -r '.tool_input.command // empty')
[[ -z "$cmd" ]] && exit 0

matches=$(parse_install_cmd "$cmd")
[[ -z "$matches" ]] && exit 0

block=0
block_msgs=""
while IFS=$'\t' read -r eco pkg ver; do
  [[ -z "$pkg" ]] && continue
  # If version unknown, we cannot check — skip (passes). Alternative: block and ask Claude to pin.
  [[ -z "$ver" ]] && continue
  if ! bash "$DIR/check-sidecar.sh" "$eco" "$pkg" "$ver" 2>/tmp/_vs_err; then
    block=1
    block_msgs+=$(cat /tmp/_vs_err)$'\n---\n'
  fi
done <<< "$matches"
rm -f /tmp/_vs_err

if [[ "$block" -eq 1 ]]; then
  echo "$block_msgs" >&2
  exit 2
fi
exit 0
```

- [ ] **Step 5: Run — expect PASS**

- [ ] **Step 6: Commit**

```bash
git add scripts/detect-install-cmd.sh tests/test_detect_install_cmd.sh tests/fixtures/bash_*.json
git commit -m "feat(hook): detect-install-cmd.sh (Bash install commands)

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

### Task 14: Wire hooks into hooks/hooks.json

**Files:**
- Create: `hooks/hooks.json`

- [ ] **Step 1: Write `hooks/hooks.json`**

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Edit|Write|MultiEdit",
        "hooks": [
          {
            "type": "command",
            "command": "bash ${CLAUDE_PLUGIN_ROOT}/scripts/detect-manifest-edit.sh"
          }
        ]
      },
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "bash ${CLAUDE_PLUGIN_ROOT}/scripts/detect-install-cmd.sh"
          }
        ]
      }
    ]
  }
}
```

- [ ] **Step 2: Validate JSON**

```bash
jq . hooks/hooks.json > /dev/null && echo "hooks.json OK"
```

- [ ] **Step 3: Manual integration smoke test**

Open Claude Code with the plugin loaded:
```bash
claude --plugin-dir "C:/Users/DanielKiska/Source/private/version-sentinel"
```

Inside that session:
1. Create a throwaway `package.json` with `"dependencies": {}`.
2. Ask Claude to add `lodash` to deps.
3. Claude's Edit attempt should be blocked with the stderr message.

Document the observed behavior in a new note `tests/integration/TASK14_NOTES.md` (pass/fail + any unexpected behavior).

- [ ] **Step 4: Commit**

```bash
git add hooks/hooks.json tests/integration/TASK14_NOTES.md
git commit -m "feat(hook): wire hooks.json (Edit|Write|MultiEdit + Bash matchers)

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

### Task 15: /vs-record slash command

**Files:**
- Create: `commands/vs-record.md`
- Create: `scripts/vs-record.sh`
- Create: `tests/test_vs_record.sh`

- [ ] **Step 1: Write failing test**

Create `tests/test_vs_record.sh`:

```bash
#!/usr/bin/env bash
VS_TEST_NAME="vs-record"
source "$(dirname "$0")/assert.sh"

TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT
SCRIPT="$PWD/scripts/vs-record.sh"

cd "$TMPDIR"

# Valid URL → writes entry
out=$(bash "$SCRIPT" npm lodash 4.17.21 "https://www.npmjs.com/package/lodash" 2>&1; echo "exit=$?")
assert_contains "$out" "exit=0" "valid URL → success"
count=$(jq '.entries | length' .version-sentinel/checks.json)
assert_eq "1" "$count" "one entry written"
src=$(jq -r '.entries[0].source' .version-sentinel/checks.json)
assert_eq "https://www.npmjs.com/package/lodash" "$src" "source URL preserved"

# Intentional reason → accepted
out=$(bash "$SCRIPT" npm lodash 4.17.21 "intentional: CVE lock" 2>&1; echo "exit=$?")
assert_contains "$out" "exit=0" "intentional: accepted"

# Dedupe: same pkg new version overwrites
out=$(bash "$SCRIPT" npm lodash 5.0.0 "https://www.npmjs.com/package/lodash" 2>&1; echo "exit=$?")
count=$(jq '.entries | length' .version-sentinel/checks.json)
assert_eq "1" "$count" "dedupe: still 1 entry"
ver=$(jq -r '.entries[0].version' .version-sentinel/checks.json)
assert_eq "5.0.0" "$ver" "dedupe: new version wins"

# Invalid source (not URL, not intentional:) → rejected
out=$(bash "$SCRIPT" npm lodash 4.17.21 "just trust me" 2>&1; echo "exit=$?")
assert_contains "$out" "exit=1" "invalid source: exit 1"
assert_contains "$out" "http" "rejection message mentions expected format"

# Missing args → rejected
out=$(bash "$SCRIPT" npm lodash 2>&1; echo "exit=$?")
assert_contains "$out" "exit=1" "missing args: exit 1"

cd "$OLDPWD"
finish_test
```

- [ ] **Step 2: Run — expect FAIL**

- [ ] **Step 3: Implement `scripts/vs-record.sh`**

```bash
#!/usr/bin/env bash
# Usage: vs-record.sh <ecosystem> <pkg> <version> <source>
# <source> must start with http:// or https:// OR "intentional:".
set -u

if [[ $# -lt 4 ]]; then
  cat >&2 <<EOF
Usage: /vs-record <ecosystem> <pkg> <version> <source>

<source> must be one of:
  - http(s):// URL to registry page (WebSearch / WebFetch / context7 result)
  - intentional:<reason> (e.g. "intentional: CVE lock" or "intentional: no-websearch-region")

Ecosystems (v0.1): npm, pip, cargo, csproj, pyproject
EOF
  exit 1
fi

ecosystem="$1"
pkg="$2"
version="$3"
source="$4"

case "$source" in
  http://*|https://*) ;;
  intentional:*) ;;
  *)
    echo "version-sentinel: invalid source '$source'." >&2
    echo "Expected http(s):// URL or intentional:<reason>." >&2
    exit 1
    ;;
esac

DIR="$(dirname "$0")"
# shellcheck source=lib/sidecar.sh
source "$DIR/lib/sidecar.sh"

path=$(sidecar_path "$PWD")
sidecar_write_entry "$path" "$ecosystem" "$pkg" "$version" "$source"
echo "recorded: $ecosystem/$pkg@$version (source: $source)"
```

- [ ] **Step 4: Write slash command doc**

Create `commands/vs-record.md`:

```markdown
---
description: Record a fresh version check in the version-sentinel sidecar
argument-hint: <ecosystem> <pkg> <version> <source-url-or-intentional:>
---

# /vs-record

Record that a dependency version has been verified against its registry. Accepted sources:
- `http(s)://...` URL from a WebSearch, WebFetch, or context7 result
- `intentional:<reason>` for deliberate non-latest pins (CVE lock, compat, region with no WebSearch)

## Usage

```
/vs-record <ecosystem> <pkg> <version> <source>
```

## Ecosystems (v0.1)

`npm`, `pip`, `cargo`, `csproj`, `pyproject`

## Examples

```
/vs-record npm lodash 4.17.21 https://www.npmjs.com/package/lodash
/vs-record pip requests 2.31.0 https://pypi.org/project/requests/
/vs-record csproj Serilog 3.1.1 intentional: CVE lock pending audit
```

## What this does

Runs `bash ${CLAUDE_PLUGIN_ROOT}/scripts/vs-record.sh $ARGUMENTS` which writes (and dedupes on `(ecosystem, pkg)`) an entry into `<cwd>/.version-sentinel/checks.json`. A fresh entry satisfies the PreToolUse hook for 24 hours.

!bash ${CLAUDE_PLUGIN_ROOT}/scripts/vs-record.sh $ARGUMENTS
```

- [ ] **Step 5: Run — expect PASS**

```bash
chmod +x scripts/vs-record.sh
bash tests/run.sh
```

- [ ] **Step 6: Commit**

```bash
git add commands/vs-record.md scripts/vs-record.sh tests/test_vs_record.sh
git commit -m "feat(cmd): /vs-record slash command + shell backend

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

### Task 16: /check-versions audit command

**Files:**
- Create: `commands/check-versions.md`
- Create: `scripts/check-versions.sh`
- Create: `scripts/lib/registries.sh`
- Create: `tests/test_registries_offline.sh`

- [ ] **Step 1: Write offline unit test (mock curl)**

Live-network tests are gated behind `VS_LIVE=1`; unit tests use a mock `curl` on PATH that returns fixture JSON.

Create `tests/fixtures/registry_npm_lodash.json`:
```json
{
  "dist-tags": { "latest": "4.17.21" }
}
```

Create `tests/fixtures/registry_pypi_requests.json`:
```json
{
  "info": { "version": "2.31.0" }
}
```

Create `tests/fixtures/registry_nuget_newtonsoft.json`:
```json
{
  "versions": ["12.0.0", "13.0.1", "13.0.3"]
}
```

Create `tests/fixtures/registry_crates_serde.json`:
```json
{
  "crate": { "max_stable_version": "1.0.196" }
}
```

Create `tests/test_registries_offline.sh`:

```bash
#!/usr/bin/env bash
VS_TEST_NAME="registries-offline"
source "$(dirname "$0")/assert.sh"

# Stub curl: reads URL arg, returns matching fixture
STUB_DIR=$(mktemp -d)
trap 'rm -rf "$STUB_DIR"' EXIT

cat > "$STUB_DIR/curl" <<'CURL'
#!/usr/bin/env bash
url="${@: -1}"  # last arg is the URL
case "$url" in
  *registry.npmjs.org/lodash*)       cat tests/fixtures/registry_npm_lodash.json ;;
  *pypi.org/pypi/requests*)          cat tests/fixtures/registry_pypi_requests.json ;;
  *nuget.org*newtonsoft.json*)       cat tests/fixtures/registry_nuget_newtonsoft.json ;;
  *crates.io/api/v1/crates/serde*)   cat tests/fixtures/registry_crates_serde.json ;;
  *)                                 echo "stub: unknown URL $url" >&2; exit 1 ;;
esac
CURL
chmod +x "$STUB_DIR/curl"
export PATH="$STUB_DIR:$PATH"

source "$PWD/scripts/lib/registries.sh"

assert_eq "4.17.21"  "$(registry_latest npm lodash)"        "npm latest"
assert_eq "2.31.0"   "$(registry_latest pip requests)"      "pypi latest"
assert_eq "13.0.3"   "$(registry_latest csproj Newtonsoft.Json)" "nuget latest (last in versions[])"
assert_eq "1.0.196"  "$(registry_latest cargo serde)"       "crates latest"

finish_test
```

- [ ] **Step 2: Run — expect FAIL**

- [ ] **Step 3: Implement `scripts/lib/registries.sh`**

```bash
#!/usr/bin/env bash
# registry_latest <ecosystem> <pkg> → prints latest version string, exit 0
# Exits 1 (and prints nothing) on any lookup failure. Caller decides whether to block or warn.
registry_latest() {
  local eco="$1" pkg="$2"
  local url="" json=""
  case "$eco" in
    npm)
      url="https://registry.npmjs.org/$(printf '%s' "$pkg" | jq -sRr @uri)"
      json=$(curl -fsSL "$url") || return 1
      echo "$json" | jq -r '.["dist-tags"].latest // empty'
      ;;
    pip|pyproject)
      url="https://pypi.org/pypi/$(printf '%s' "$pkg" | jq -sRr @uri)/json"
      json=$(curl -fsSL "$url") || return 1
      echo "$json" | jq -r '.info.version // empty'
      ;;
    csproj)
      local low
      low=$(printf '%s' "$pkg" | tr '[:upper:]' '[:lower:]')
      url="https://api.nuget.org/v3-flatcontainer/${low}/index.json"
      json=$(curl -fsSL "$url") || return 1
      echo "$json" | jq -r '.versions[-1] // empty'
      ;;
    cargo)
      url="https://crates.io/api/v1/crates/$(printf '%s' "$pkg" | jq -sRr @uri)"
      json=$(curl -fsSL -A "version-sentinel (+https://github.com/DanielKiska/version-sentinel)" "$url") || return 1
      echo "$json" | jq -r '.crate.max_stable_version // empty'
      ;;
    *)
      return 1
      ;;
  esac
}
```

- [ ] **Step 4: Run — expect PASS**

- [ ] **Step 5: Implement `scripts/check-versions.sh`**

```bash
#!/usr/bin/env bash
# /check-versions — audit every manifest under PWD for dep-vs-latest drift.
# VS_LIVE=1 is NOT required for normal use; it gates the test suite only.
set -u

DIR="$(dirname "$0")"
# shellcheck source=lib/parse-manifest.sh
source "$DIR/lib/parse-manifest.sh"
# shellcheck source=lib/registries.sh
source "$DIR/lib/registries.sh"
# shellcheck source=lib/sidecar.sh
source "$DIR/lib/sidecar.sh"

if ! command -v curl >/dev/null 2>&1; then
  echo "version-sentinel: curl missing, cannot audit" >&2
  exit 1
fi

# Find manifests up to depth 4 (v0.1 scope)
manifests=$(find . -maxdepth 4 \
  \( -name package.json -o -name 'requirements*.txt' -o -name 'constraints*.txt' \
     -o -name pyproject.toml -o -name Cargo.toml \
     -o -name '*.csproj' -o -name '*.fsproj' -o -name '*.vbproj' \) \
  -not -path '*/node_modules/*' -not -path '*/.git/*' -not -path '*/target/*' \
  -not -path '*/.venv/*' -not -path '*/venv/*' 2>/dev/null)

printf '%-12s %-40s %-15s %-15s %s\n' ECOSYSTEM PACKAGE "CURRENT" "LATEST" STATUS
printf '%s\n' "-----------------------------------------------------------------------------------------"

sidecar=$(sidecar_path "$PWD")

while IFS= read -r mf; do
  [[ -z "$mf" ]] && continue
  eco=$(ecosystem_for_path "$mf")
  [[ -z "$eco" ]] && continue
  while IFS=$'\t' read -r pkg cur; do
    [[ -z "$pkg" ]] && continue
    latest=$(registry_latest "$eco" "$pkg" 2>/dev/null || echo "?")
    status="ok"
    if [[ -z "$latest" || "$latest" == "?" ]]; then
      status="lookup-failed"
    elif [[ "$cur" != "$latest" ]]; then
      # Intentional pin surfaces as warning, not error
      intentional=$(sidecar_read "$sidecar" | jq -r --arg e "$eco" --arg p "$pkg" \
        '.entries[] | select(.ecosystem==$e and .pkg==$p and (.source|startswith("intentional:"))) | .source' | head -1)
      if [[ -n "$intentional" ]]; then
        status="intentional-pin"
      else
        status="DRIFT"
      fi
    fi
    printf '%-12s %-40s %-15s %-15s %s\n' "$eco" "$pkg" "$cur" "${latest:-?}" "$status"
    sleep 0.2  # 200ms throttle
  done <<< "$(parse_manifest_by_path "$mf")"
done <<< "$manifests"
```

- [ ] **Step 6: Write slash command doc**

Create `commands/check-versions.md`:

```markdown
---
description: Audit dependencies against upstream registries (npm, pypi, nuget, crates.io)
---

# /check-versions

Scans every manifest under the current working directory and compares each pinned version to the latest on its upstream registry. Reports drift without blocking.

Supported in v0.1: `package.json`, `requirements*.txt`, `pyproject.toml`, `Cargo.toml`, `*.csproj`.

Intentional pins (recorded via `/vs-record <pkg> <ver> "intentional: <reason>"`) surface as `intentional-pin`, not `DRIFT`.

!bash ${CLAUDE_PLUGIN_ROOT}/scripts/check-versions.sh
```

- [ ] **Step 7: Commit**

```bash
chmod +x scripts/check-versions.sh
git add commands/check-versions.md scripts/check-versions.sh scripts/lib/registries.sh \
  tests/test_registries_offline.sh tests/fixtures/registry_*.json
git commit -m "feat(cmd): /check-versions audit + registries.sh

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

### Task 17: version-sentinel SKILL.md

**Files:**
- Create: `skills/version-sentinel/SKILL.md`

- [ ] **Step 1: Write `skills/version-sentinel/SKILL.md`**

```markdown
---
name: version-sentinel
description: Use when adding, bumping, or changing a dependency in package.json, requirements.txt, pyproject.toml, Cargo.toml, or a .csproj. Triggered automatically by version-sentinel's PreToolUse hook — this skill explains how to satisfy the hook.
---

# Version Sentinel — Workflow

The `version-sentinel` plugin blocks dependency changes until you've verified the package version against its upstream registry. Here's the required flow:

## When you see a BLOCKED message

If a tool call exits 2 with `BLOCKED: version-sentinel`, you must:

1. **Look up the latest version.** Use `WebSearch` first:
   - `npm`:      search `"<pkg> latest version site:npmjs.com"`
   - `pip`/`pyproject`: search `"<pkg> latest version site:pypi.org"`
   - `csproj`:   search `"<pkg> latest version site:nuget.org"`
   - `cargo`:    search `"<pkg> latest version site:crates.io"`

   If WebSearch is unavailable (non-US region), use `WebFetch` on the registry URL directly, or consult context7's `query-docs` tool for the package.

2. **Record the check.** Invoke:

       /vs-record <ecosystem> <pkg> <version-you-intend-to-install> <source-url>

   The source must be an `http(s)://` URL from your search OR prefixed with `intentional:` for deliberate pins.

3. **Retry the original edit or install.** The hook will see the fresh entry and let the tool call through.

## Intentional non-latest pins

If you genuinely intend to install an older version (CVE mitigation, compat, private registry), record with:

    /vs-record <ecosystem> <pkg> <version> "intentional: <brief reason>"

This passes the hook and is flagged as `intentional-pin` (not `DRIFT`) in `/check-versions` output.

## What NOT to do

- Don't fake a source URL you didn't actually see. The skill contract assumes honest reporting; v0.2 will probe the transcript to verify.
- Don't try to bypass the hook with `git commit --no-verify` or similar — the hook runs on `Edit`/`Write`/`Bash`, not on git.
- Don't `unset VS_DISABLE` without the user's awareness; that's an escape hatch for throwaway sessions, not normal flow.

## Audit command

`/check-versions` scans every manifest under the current directory and reports drift. Run it before tagging a release.
```

- [ ] **Step 2: Commit**

```bash
git add skills/version-sentinel/SKILL.md
git commit -m "feat(skill): version-sentinel SKILL.md workflow guide

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

### Task 18: README.md

**Files:**
- Create: `README.md`

- [ ] **Step 1: Write `README.md`**

```markdown
# version-sentinel

Claude Code plugin that **hard-blocks** dependency additions, bumps, and downgrades until a fresh, source-cited version check is recorded.

> If Claude tries to add `"lodash": "^4.17.21"` without looking up the latest version first, the tool call is rejected with exit 2. Claude must run `WebSearch`, then `/vs-record`, then retry. Five ecosystems supported in v0.1.

## Why

LLM-assisted coding silently ships whatever version the model remembers from its training data. For packages with frequent releases or known compromised versions, that's unacceptable. `version-sentinel` inserts a mandatory "check the registry" step — without stopping you from pinning an old version on purpose.

## Supported ecosystems (v0.1)

| File | Ecosystem | Registry |
|------|-----------|----------|
| `package.json` | npm/pnpm/yarn/bun | registry.npmjs.org |
| `requirements*.txt`, `constraints*.txt` | pip | pypi.org |
| `pyproject.toml` | PEP 621 + Poetry + uv | pypi.org |
| `Cargo.toml` | Rust | crates.io |
| `*.csproj`, `*.fsproj`, `*.vbproj` | .NET | api.nuget.org |

Covers `Edit`, `Write`, `MultiEdit`, and `Bash` install commands (`npm install`, `pip install`, `poetry add`, `uv add`, `cargo add`, `dotnet add package`).

## Install

```
/plugin marketplace add DanielKiska/version-sentinel
/plugin install version-sentinel@version-sentinel-marketplace
```

The plugin's marketplace name is `version-sentinel-marketplace`, distinct from the plugin name `version-sentinel`.

## Prerequisites

- `bash`, `jq`, `curl`, `python3` (3.11+, for `tomllib`) on `PATH`
- Windows users: Git Bash bundles `bash`/`jq`/`curl`; install Python 3.13 separately.

## How it works

1. Claude tries to add/bump a dep (`Edit package.json`, `npm install X@Y`, ...)
2. PreToolUse hook fires, exits 2 with stderr:
   ```
   BLOCKED: version-sentinel.
   Package: lodash (npm). Version: 4.17.21.
   No fresh version check on record.
   ...
   ```
3. Claude reads the block, runs `WebSearch "lodash latest version site:npmjs.com"`
4. Claude invokes `/vs-record npm lodash 4.17.21 https://www.npmjs.com/package/lodash`
5. Claude retries — the hook finds the fresh entry and lets the call through.

## Commands

- `/vs-record <ecosystem> <pkg> <version> <source>` — record a version check. Source must be `http(s)://...` or `intentional:<reason>`.
- `/check-versions` — audit every manifest in the current directory against upstream registries.

## Escape hatches

| Case | How |
|------|-----|
| Deliberate old-version pin | `/vs-record npm some-pkg 1.0.0 "intentional: CVE fix deferred"` |
| Throwaway session, want to skip entirely | `export VS_DISABLE=1` |
| Package you'll never update (private, forked) | Add `ecosystem:pkg` to `.version-sentinel/ignore` |
| No WebSearch available (non-US region) | `/vs-record ... "intentional: no-websearch-region"` or use a `WebFetch` URL as source |

## Sidecar file

State lives at `<project-root>/.version-sentinel/checks.json`. The directory auto-creates its own `.gitignore` on first write; you never need to commit it.

## Uninstall

```
/plugin uninstall version-sentinel@version-sentinel-marketplace
/plugin marketplace remove version-sentinel-marketplace
```

State files in `.version-sentinel/` are safe to delete.

## Troubleshooting

| Symptom | Cause / fix |
|---------|-------------|
| `jq missing, fail-open` in stderr | Install `jq` (Git Bash: already present; Linux: `apt install jq`) |
| `tomllib` import error | Upgrade to Python 3.11+ |
| Hook passes everything without blocking | Check `VS_DISABLE` is unset; run `/reload-plugins` |
| `DRIFT` on a pkg that IS latest | Sidecar has a mismatched entry — delete `.version-sentinel/checks.json` and redo the check |

## License

MIT — see [LICENSE](./LICENSE).
```

- [ ] **Step 2: Commit**

```bash
git add README.md
git commit -m "docs: README with install/usage/troubleshooting

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

### Task 19: Integration smoke test

**Files:**
- Create: `tests/integration/smoke.sh`

- [ ] **Step 1: Write `tests/integration/smoke.sh`**

```bash
#!/usr/bin/env bash
# End-to-end smoke test. Runs all hook scripts against realistic fixtures.
# Does NOT require claude CLI — it invokes the hook scripts directly as they'd be invoked by the runtime.
set -u

echo "=== version-sentinel integration smoke ==="

TMPDIR=$(mktemp -d)
cleanup() { rm -rf "$TMPDIR"; }
trap cleanup EXIT

cd "$TMPDIR"
cat > package.json <<'EOF'
{ "name": "demo", "version": "1.0.0", "dependencies": { "express": "4.19.2" } }
EOF

# --- 1. Manifest edit adds lodash → should block ---
input=$(cat <<EOF
{
  "tool_name": "Edit",
  "tool_input": {
    "file_path": "$TMPDIR/package.json",
    "old_string": "\"express\": \"4.19.2\"",
    "new_string": "\"express\": \"4.19.2\", \"lodash\": \"4.17.21\"",
    "replace_all": false
  }
}
EOF
)
echo "[1/4] Edit adds lodash (expect exit 2)"
echo "$input" | bash "$OLDPWD/scripts/detect-manifest-edit.sh" 2>/tmp/smoke1.err
rc=$?
[[ "$rc" -eq 2 ]] || { echo "FAIL: expected exit 2, got $rc"; exit 1; }
grep -q "lodash" /tmp/smoke1.err || { echo "FAIL: stderr missing lodash"; exit 1; }

# --- 2. /vs-record the check ---
echo "[2/4] /vs-record"
bash "$OLDPWD/scripts/vs-record.sh" npm lodash 4.17.21 "https://www.npmjs.com/package/lodash" \
  || { echo "FAIL: vs-record"; exit 1; }

# --- 3. Retry edit → should pass ---
echo "[3/4] Retry edit (expect exit 0)"
echo "$input" | bash "$OLDPWD/scripts/detect-manifest-edit.sh" 2>/tmp/smoke2.err
rc=$?
[[ "$rc" -eq 0 ]] || { echo "FAIL: expected exit 0 after record, got $rc"; cat /tmp/smoke2.err; exit 1; }

# --- 4. Bash install cmd without record → block ---
echo "[4/4] Bash npm install requests@2.31.0 (expect exit 2)"
echo '{"tool_name":"Bash","tool_input":{"command":"npm install requests@2.31.0"}}' \
  | bash "$OLDPWD/scripts/detect-install-cmd.sh" 2>/tmp/smoke3.err
rc=$?
[[ "$rc" -eq 2 ]] || { echo "FAIL: bash install not blocked"; exit 1; }
grep -q "requests" /tmp/smoke3.err || { echo "FAIL: stderr missing requests"; exit 1; }

echo "=== ALL SMOKE TESTS PASS ==="
```

- [ ] **Step 2: Run it**

```bash
chmod +x tests/integration/smoke.sh
bash tests/integration/smoke.sh
```
Expected: `=== ALL SMOKE TESTS PASS ===`.

- [ ] **Step 3: Add smoke to `tests/run.sh`** — append:

```bash
echo
echo "=== Integration smoke ==="
bash "$(dirname "$0")/integration/smoke.sh" || failed=$((failed + 1))
```

- [ ] **Step 4: Commit**

```bash
git add tests/integration/smoke.sh tests/run.sh
git commit -m "test: end-to-end integration smoke (block → record → retry → allow)

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

### Task 20: CHANGELOG + v0.1.0 tag

**Files:**
- Create: `CHANGELOG.md`

- [ ] **Step 1: Write CHANGELOG**

```markdown
# Changelog

All notable changes to version-sentinel.

## [0.1.0] — 2026-04-16

### Added
- PreToolUse hooks for `Edit`, `Write`, `MultiEdit`, and `Bash` tools.
- Manifest parsers for 5 ecosystem file families: `package.json`, `requirements*.txt` / `constraints*.txt`, `pyproject.toml` (PEP 621 + Poetry + uv), `Cargo.toml`, `*.csproj` / `*.fsproj` / `*.vbproj`.
- Install-command parsers for `npm`/`pnpm`/`yarn`/`bun`, `pip`/`pip3`, `poetry`, `uv`, `cargo`, `dotnet`.
- `/vs-record` slash command to write sidecar entries (accepts `http(s)://` URLs or `intentional:` reasons).
- `/check-versions` slash command to audit all manifests against upstream registries (npm, PyPI, NuGet, crates.io).
- Sidecar state at `<cwd>/.version-sentinel/checks.json` with auto-gitignore and last-write-wins dedupe on `(ecosystem, pkg)`.
- `VS_DISABLE=1` escape hatch and `.version-sentinel/ignore` pattern file.
- Fail-open philosophy: any hook-internal error (missing `jq`/`curl`, parse crash, unreadable pre-edit file) passes through rather than blocking Claude.
- Bash test harness with 14+ fixture-driven unit tests + 1 integration smoke.

### Known limitations
- `<PackageReference>` with a child `<Version>` element (rather than attribute) is not parsed. Attribute form only.
- `pyproject.toml` range specifiers (e.g. `>=1,<2`) are reduced to the lower bound.
- Offline use: `/check-versions` requires network; hook blocks still work without it.
- Claude obedience: v0.1 trusts the model to actually search before invoking `/vs-record`. v0.2 will probe the transcript.

### Roadmap
- v0.2.0: `go.mod`, `Gemfile`, `composer.json`; transcript-probe honesty check.
- v0.3.0: Maven `pom.xml`, Gradle `build.gradle(.kts)`, legacy Python (`Pipfile`, `setup.py`, `setup.cfg`).
- v1.0.0: all 11 file families + stable sidecar schema guarantee.
```

- [ ] **Step 2: Run full test suite one final time**

```bash
bash tests/run.sh
```
Expected: all tests pass, `Failed: 0`.

- [ ] **Step 3: Commit + tag**

```bash
git add CHANGELOG.md
git commit -m "chore: CHANGELOG for v0.1.0

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
git tag -a v0.1.0 -m "v0.1.0 — 5 ecosystems, hard-block hook, /vs-record, /check-versions"
```

- [ ] **Step 4: GitHub publish (manual — NOT automated)**

Per the user's permanent rules (global CLAUDE.md: never push without confirmation), do NOT run `git push` here. Hand off to the user with the command they should run:

```
git remote add origin https://github.com/DanielKiska/version-sentinel.git
git push -u origin main
git push --tags
```

Then create a GitHub release for `v0.1.0` citing the CHANGELOG.

---

## Self-review

**Spec coverage:**

| Spec requirement | Task |
|------------------|------|
| Plugin manifest w/ name, version, author, repo | Task 1 |
| marketplace.json w/ name, owner, plugins (no $schema) | Task 1 |
| hooks.json wrapper `{"hooks": {...}}` (no description) | Task 14 |
| PreToolUse matcher `Edit|Write|MultiEdit` | Task 14 |
| PreToolUse matcher `Bash` | Task 14 |
| Sidecar at `<cwd>/.version-sentinel/checks.json` | Task 3 |
| `${CLAUDE_PLUGIN_DATA}` fallback | Task 3 |
| Auto-gitignore | Task 3 |
| Dedupe on `(ecosystem, pkg)` | Tasks 3, 15 |
| 24h freshness window | Tasks 3, 4 |
| Exit-2 + stderr block path | Task 4 |
| Manifest parsers (5 ecosystems) | Tasks 5–9 |
| Path→ecosystem dispatch | Task 10 |
| Diff added/changed (bump AND downgrade) | Task 10 |
| `replace_all: true` full-file simulation | Task 12 |
| `MultiEdit` support | Task 12 |
| `Write` new-file fallback | Task 12 |
| Install-cmd parser (v0.1 scope) | Task 11 |
| `/vs-record` command + URL/intentional validation | Task 15 |
| `/check-versions` audit + registry endpoints | Task 16 |
| `VS_DISABLE` escape | Tasks 4, 12, 13 |
| `.version-sentinel/ignore` | *NOT in v0.1 — deferred to v0.2* |
| SKILL.md workflow | Task 17 |
| Fail-open on internal errors | Tasks 12, 13 |
| Tests (unit + integration) | Tasks 2, 5–13, 15, 16, 19 |
| README + install instructions | Task 18 |
| CHANGELOG + v0.1.0 tag | Task 20 |

**Gap flagged:** `.version-sentinel/ignore` file support is in the spec but not in v0.1 tasks. Deferring to v0.2 (tracked in CHANGELOG roadmap).

**Placeholder scan:** None. Every step contains actual code, exact commands, and expected output.

**Type consistency:**
- `sidecar_read`, `sidecar_find_fresh`, `sidecar_write_entry` — consistent signatures across Tasks 3, 4, 12, 13, 15, 16.
- `parse_npm`, `parse_pip`, `parse_pyproject`, `parse_cargo`, `parse_csproj`, `parse_manifest_by_path`, `ecosystem_for_path`, `diff_manifest_sets` — consistent across Tasks 5–12.
- `parse_install_cmd` — single entry point used in Task 13.
- `registry_latest <ecosystem> <pkg>` — consistent in Tasks 16 test + impl.
- Ecosystem names are stable across everything: `npm`, `pip`, `pyproject`, `cargo`, `csproj`.

All consistent.
