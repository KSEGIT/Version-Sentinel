#!/usr/bin/env bash
# Guards the `if` gate on the Bash hooks in hooks/hooks.json.
#
# detect-install-cmd.sh and auto-record.sh used to spawn on every single Bash
# tool call and exit 0 immediately for the ~98% that are not installs. They are
# now gated behind Claude Code `if` rules (permission-rule syntax), keyed on the
# package-manager binary rather than the subcommand so that `npm i`, `npm add`
# and `npm install` are all covered by one rule.
#
# The rules must stay in sync with the command names lib/parse-install-cmd.sh
# recognizes. A manager the parser knows but no `if` rule covers is a SILENT
# BYPASS, not a slowdown — hence this test.
#
# Must stay bash 3.2 clean (stock macOS /bin/bash, and the macos-latest CI leg):
# no mapfile, and no bare ${arr[@]} on a possibly-empty array under `set -u`.
# An earlier revision used mapfile and, on 3.2, aborted its own parity loop and
# still printed PASS — it reported green with the npm rule deleted. Hence
# checked_events below: if a loop is ever skipped, the test fails instead.
#
# RULE SHAPE IS LOAD-BEARING. The rules are `Bash(*<mgr> *)`, not
# `Bash(<mgr> *)`. Measured on Claude Code 2.1.227:
#
#   command form                     Bash(npm *)   Bash(*npm *)
#   npm ...                              fires        fires
#   FOO=bar npm ...                      fires        fires    (assignments stripped)
#   timeout 30 npm ... / nice npm ...   DOES NOT      fires
#
# The hooks reference claims process wrappers are stripped before rule
# matching; they are not, for `if`. Since lib/parse-install-cmd.sh now strips
# those wrappers via _strip_cmd_prefix and therefore blocks the prefixed forms,
# a narrowed `Bash(<mgr> *)` rule would mean the hook never spawns to run that
# logic — the parser would pass its unit tests while the guard stayed off.
# Widening costs ~1% of Bash calls in extra spawns, measured over 26,917 calls.
#
# KNOWN OVERLAP, deliberate. Glob `*npm *` also matches `pnpm add x` (the `*`
# absorbs the `p`), and `uv pip install x` matches both `*uv *` and `*pip *`, so
# those commands fire two identical handlers and emit the block message twice.
# One rule per manager is kept anyway: it keeps intent obvious and lets the
# parity check below be a simple per-manager assertion. Measured cost over
# 27,028 Bash calls: 44 commands (0.163%) match more than one rule.
#
# Forms verified blocked end-to-end with the gate on: a pinned install behind a
# `cd ... &&` compound; the same split across two lines by a bare newline; one
# behind `;`; one behind `||`; doubled spaces; a pinned pip3 install; and each
# of the wrapper and assignment prefixes above.
set -u
VS_TEST_NAME="hook-if-parity"
source "$(dirname "$0")/assert.sh"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HOOKS="$ROOT/hooks/hooks.json"
PARSER="$ROOT/scripts/lib/parse-install-cmd.sh"

assert_file_exists "$HOOKS" "hooks.json present"
assert_file_exists "$PARSER" "parse-install-cmd.sh present"
assert_eq "0" "$(jq empty "$HOOKS" >/dev/null 2>&1; echo $?)" "hooks.json is valid JSON"

# --- Managers the parser recognizes, read out of its own source -------------
# Every branch of _parse_install_segment has the shape
#   if [[ "$seg" =~ ^(npm|pnpm|yarn|bun)[[:space:]]+(add|install|i)... ]]
#   if [[ "$seg" =~ ^pip3?[[:space:]]+install... ]]
# so the command-name part is whatever sits between `=~ ^` and the first
# [[:space:]]. Deriving it here means adding a manager to the parser without a
# matching hook rule fails this test instead of silently disabling the guard.
# The class must admit `.`, `_` and `-` so a future `apt-get`/`pip_tools`
# branch cannot slip through extraction unnoticed.
EXTRACT='s/.*"\$seg"[[:space:]]+=~[[:space:]]+\^(\(?[A-Za-z0-9._|?-]+\)?)\[\[:space:\]\].*/\1/p'

# Every parser branch must yield exactly one token. If sed's class ever fails to
# cover a manager name, tokens < branches and this fails loudly rather than
# quietly dropping that manager from the parity check below.
# Scope to _parse_install_segment's body only. Sibling helpers such as
# _strip_cmd_prefix match on "$seg" too, but their regexes are wrapper and
# assignment patterns, not manager names.
SEGBODY=$(awk '/^_parse_install_segment\(\) \{/{f=1;next} f&&/^\}/{exit} f' "$PARSER")
if [[ -z "$SEGBODY" ]]; then
  _fail "could not slice _parse_install_segment out of $PARSER; extraction below would be vacuous"
fi
branches=$(printf '%s\n' "$SEGBODY" | grep -cE '"\$seg"[[:space:]]+=~[[:space:]]+\^' | tr -d ' ')
tokens=$(printf '%s\n' "$SEGBODY" | sed -nE "$EXTRACT" | grep -c . | tr -d ' ')
assert_eq "$branches" "$tokens" "every _parse_install_segment branch yields one extracted token"

managers=""
while IFS= read -r tok; do
  [[ -z "$tok" ]] && continue
  tok="${tok#(}"; tok="${tok%)}"
  old_ifs="$IFS"; IFS='|'; set -- $tok; IFS="$old_ifs"
  for alt in "$@"; do
    if [[ "$alt" == *'?' ]]; then
      base="${alt%\?}"                       # pip3?  -> pip3
      managers="$managers $base ${base%?}"   # ...and the optional-char form: pip
    else
      managers="$managers $alt"
    fi
  done
done < <(printf '%s\n' "$SEGBODY" | sed -nE "$EXTRACT")

# Dedupe, preserving order. Space-delimited string keeps this bash 3.2 safe.
uniq_managers=""
for m in $managers; do
  case " $uniq_managers " in *" $m "*) ;; *) uniq_managers="$uniq_managers $m" ;; esac
done
n_managers=$(echo $uniq_managers | wc -w | tr -d ' ')

# A sed that quietly matches nothing would make every assertion below vacuous,
# so pin both the count and a few names we know the parser handles.
if [[ "$n_managers" -lt 8 ]]; then
  _fail "extracted only $n_managers managers from $PARSER (expected >=8): ${uniq_managers:-<none>}"
fi
for expected in npm pnpm yarn bun pip pip3 poetry uv cargo dotnet; do
  case " $uniq_managers " in
    *" $expected "*) ;;
    *) _fail "parser extraction did not find '$expected'" ;;
  esac
done

# --- Every Bash hook handler is gated, and covers every manager -------------
checked_events=0
for event in PreToolUse PostToolUse; do
  rules=""
  n_rules=0
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    rules="$rules
$line"
    n_rules=$((n_rules + 1))
  done < <(jq -r --arg ev "$event" \
    '.hooks[$ev][]? | select(.matcher == "Bash") | .hooks[] | (.if // "<UNGATED>")' "$HOOKS")

  if [[ "$n_rules" -eq 0 ]]; then
    _fail "$event: no Bash hook group found in hooks.json"
    continue
  fi

  case "$rules" in
    *"<UNGATED>"*) _fail "$event: a Bash handler has no \`if\` rule; it would spawn on every Bash call" ;;
  esac

  # Parser -> hooks: no manager may be missing a rule (missing == silent bypass).
  for m in $uniq_managers; do
    case "$rules" in
      *"Bash(*$m *)"*) ;;
      *) _fail "$event is missing \`if\` rule 'Bash(*$m *)'" ;;
    esac
  done

  # hooks -> parser: no rule may name a manager the parser cannot handle.
  # Newline-delimited, not word-split: each rule contains a space, so `for r in
  # $rules` would split `Bash(*npm *)` into two tokens and glob-expand both.
  while IFS= read -r r; do
    [[ -z "$r" ]] && continue
    case "$r" in
      'Bash('*) ;;
      *) continue ;;
    esac
    mgr="${r#Bash(\*}"; mgr="${mgr%% \*)}"
    case " $uniq_managers " in
      *" $mgr "*) ;;
      *) _fail "$event rule 'Bash(*$mgr *)' names a manager parse-install-cmd.sh does not recognize" ;;
    esac
  done <<EOF
$rules
EOF

  checked_events=$((checked_events + 1))
done

# If the loop above is ever skipped (as it silently was under bash 3.2 with
# mapfile), every assertion in it is skipped too. Fail rather than pass green.
assert_eq "2" "$checked_events" "parity loop ran for both PreToolUse and PostToolUse"

# --- The manifest-edit hook is deliberately NOT gated ----------------------
# Edit/Write/MultiEdit are a small share of tool calls, and `if` matches the
# literal tool name (an Edit(...) rule does not fire for the Write tool), so
# gating that group buys little and risks a manifest pattern silently going
# unguarded. Keep it firing on everything.
ungated=$(jq '[.hooks.PreToolUse[]? | select(.matcher != "Bash") | .hooks[] | select(has("if"))] | length' "$HOOKS")
assert_eq "0" "$ungated" "manifest-edit hook stays ungated on purpose"

# --- Codex gets its own UNGATED copy --------------------------------------
# Measured on codex-cli 0.151.0: Codex loads hooks/hooks.json fine but ignores
# the `if` field entirely — it ran the hook for `echo hi`, which no rule
# matches. Because it ignores `if`, it runs every handler in the group, so the
# 10 gated handlers meant 10 spawns of each script per shell command (20 total,
# vs 2 before). Not a guard hole — the hook still fires and still blocks — but a
# 10x overhead regression on that platform. So .codex-plugin/plugin.json points
# at hooks/codex-hooks.json, which is the same wiring with one handler per
# group and no `if`. The two files must not otherwise drift.
CODEX_HOOKS="$ROOT/hooks/codex-hooks.json"
CODEX_MANIFEST="$ROOT/.codex-plugin/plugin.json"

assert_file_exists "$CODEX_HOOKS" "codex-hooks.json present"
assert_eq "0" "$(jq empty "$CODEX_HOOKS" >/dev/null 2>&1; echo $?)" "codex-hooks.json is valid JSON"
assert_eq "./hooks/codex-hooks.json" "$(jq -r '.hooks' "$CODEX_MANIFEST" 2>/dev/null)" \
  ".codex-plugin/plugin.json points at the ungated copy"

n_if=$(jq '[.hooks[][].hooks[] | select(has("if"))] | length' "$CODEX_HOOKS")
assert_eq "0" "$n_if" "codex-hooks.json carries no \`if\` keys"

# Same events, matchers and scripts in both files — `if` and the resulting
# handler duplication are the only permitted difference.
_wiring() {
  jq -S -c '.hooks | to_entries
            | map({event: .key,
                   groups: (.value | map({matcher: (.matcher // "*"),
                                          cmds: (.hooks | map(.command) | unique)}))})' "$1"
}
assert_eq "$(_wiring "$CODEX_HOOKS")" "$(_wiring "$HOOKS")" \
  "codex-hooks.json wires the same events/matchers/scripts as hooks.json"

# _wiring uses `unique`, so a DUPLICATED handler would compare equal. Codex runs
# every handler in a group, so a duplicate there is exactly the 10x-spawn
# regression this file was split off to avoid. Pin the count as well.
dupes=$(jq '[.hooks[][] | select((.hooks | length) != 1)] | length' "$CODEX_HOOKS")
assert_eq "0" "$dupes" "every codex-hooks.json group has exactly one handler"


finish_test
