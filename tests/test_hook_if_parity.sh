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
# RULE SHAPE IS LOAD-BEARING. The rules are `Bash(*<mgr>*)` -- leading star, and
# NO trailing space. Measured on Claude Code 2.1.227:
#
#   command form                       Bash(npm *)  Bash(*npm *)  Bash(*npm*)
#   npm ...                              fires        fires        fires
#   FOO=bar npm ...                      fires        fires        fires
#   timeout 30 npm ... / nice npm ...   DOES NOT      fires        fires
#   npm<TAB>install ...                 DOES NOT     DOES NOT      fires
#
# The leading star covers process wrappers, which the hooks reference claims are
# stripped before rule matching but are not, for `if`. Dropping the trailing
# space closes a whitespace mismatch: _parse_install_segment anchors on
# [[:space:]]+, so it parses a TAB-separated install, but the glob `*npm *`
# requires a literal space and would never spawn the hook to run it -- a silent
# bypass, not a slowdown. Measured over 27,222 Bash calls: 3.81% -> 6.75% of
# calls spawn, still a 93% reduction on the ungated 100%.
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
branches=$(printf '%s\n' "$SEGBODY" | grep -cE '"\$seg"[[:space:]]+=~[[:space:]]+\^' | tr -d ' \r')
tokens=$(printf '%s\n' "$SEGBODY" | sed -nE "$EXTRACT" | grep -c . | tr -d ' \r')
assert_eq "$branches" "$tokens" "every _parse_install_segment branch yields one extracted token"

managers=""
while IFS= read -r tok; do
  tok="${tok%$'\r'}"          # jq/sed on Git Bash can emit CRLF
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
    # Under Git Bash it is the `< <(...)` PROCESS-SUBSTITUTION readers that
    # deliver CRLF, not jq generally: in the failing Windows run the plain
    # $(jq ...) assertions all passed. The tr -d '\r' on those sites is
    # belt-and-braces; this strip is the one that was actually required. The
    # rule for future edits is: any new `< <(...)` reader needs a CR strip.
    line="${line%$'\r'}"
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

  # Parser -> hooks: every manager must be COVERED (missing == silent bypass).
  # A rule `Bash(*r*)` matches any command text containing r, so it covers
  # manager m whenever r is a substring of m: `Bash(*npm*)` covers pnpm and
  # `Bash(*pip*)` covers pip3. Coverage is the property that matters, not one
  # rule per manager -- demanding the latter cemented redundant rules that make
  # those two managers fork the hook script twice per call.
  for m in $uniq_managers; do
    covered=0
    while IFS= read -r r; do
      r="${r%$'\r'}"
      [[ -z "$r" ]] && continue
      tok="${r#Bash(\*}"; tok="${tok%%\*)}"
      [[ -z "$tok" ]] && continue
      case "$m" in *"$tok"*) covered=1; break ;; esac
    done <<EOF
$rules
EOF
    assert_eq "1" "$covered" "$event covers manager '$m'"
  done

  # ...and the rule set must be MINIMAL: if one rule's token is a substring of
  # another's, the shorter already matches everything the longer does, so the
  # longer only forks the script a second time.
  while IFS= read -r r1; do
    r1="${r1%$'\r'}"; [[ -z "$r1" ]] && continue
    t1="${r1#Bash(\*}"; t1="${t1%%\*)}"; [[ -z "$t1" ]] && continue
    while IFS= read -r r2; do
      r2="${r2%$'\r'}"; [[ -z "$r2" ]] && continue
      t2="${r2#Bash(\*}"; t2="${t2%%\*)}"; [[ -z "$t2" ]] && continue
      [[ "$t1" == "$t2" ]] && continue
      case "$t2" in *"$t1"*) _fail "$event rule 'Bash(*$t2*)' is redundant: 'Bash(*$t1*)' already matches it" ;; esac
    done <<EOF2
$rules
EOF2
  done <<EOF
$rules
EOF

  # hooks -> parser: no rule may name a manager the parser cannot handle.
  # Newline-delimited, not word-split: a rule can contain a space, so `for r in
  # $rules` would split it into two tokens and glob-expand both.
  checked_rules=0
  while IFS= read -r r; do
    r="${r%$'\r'}"
    [[ -z "$r" ]] && continue
    case "$r" in
      'Bash('*) ;;
      *) continue ;;
    esac
    mgr="${r#Bash(\*}"; mgr="${mgr%%\*)}"
    case " $uniq_managers " in
      *" $mgr "*) ;;
      *) _fail "$event rule 'Bash(*$mgr*)' names a manager parse-install-cmd.sh does not recognize" ;;
    esac
    checked_rules=$((checked_rules + 1))
  done <<EOF
$rules
EOF

  # Same vacuity guard as checked_events below. Every rule should reach the
  # manager check; if a future change to the jq filter above makes them all
  # `continue`, this half of the parity check silently verifies nothing.
  assert_eq "$n_rules" "$checked_rules" "$event: every rule was checked against the parser"

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
ungated=$(jq '[.hooks.PreToolUse[]? | select(.matcher != "Bash") | .hooks[] | select(has("if"))] | length' "$HOOKS" | tr -d '\r')
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
assert_eq "./hooks/codex-hooks.json" "$(jq -r '.hooks' "$CODEX_MANIFEST" 2>/dev/null | tr -d '\r')" \
  ".codex-plugin/plugin.json points at the ungated copy"

n_if=$(jq '[.hooks[][].hooks[] | select(has("if"))] | length' "$CODEX_HOOKS" | tr -d '\r')
assert_eq "0" "$n_if" "codex-hooks.json carries no \`if\` keys"

# Same events, matchers and scripts in both files — `if` and the resulting
# handler duplication are the only permitted difference.
_wiring() {
  jq -S -c '.hooks | to_entries
            | map({event: .key,
                   groups: (.value | map({matcher: (.matcher // "*"),
                                          cmds: (.hooks | map(.command) | unique)})
                                   | sort_by(.matcher))})
            | sort_by(.event)' "$1" | tr -d '\r'
}
assert_eq "$(_wiring "$CODEX_HOOKS")" "$(_wiring "$HOOKS")" \
  "codex-hooks.json wires the same events/matchers/scripts as hooks.json"

# _wiring uses `unique`, so a DUPLICATED handler would compare equal. Codex runs
# every handler in a group, so a duplicate there is exactly the 10x-spawn
# regression this file was split off to avoid. Pin the count as well.
dupes=$(jq '[.hooks[][] | select((.hooks | length) != 1)] | length' "$CODEX_HOOKS" | tr -d '\r')
assert_eq "0" "$dupes" "every codex-hooks.json group has exactly one handler"


# --- The `if` gate must never miss what the parser can detect ---------------
# The hooks reference calls `if` best-effort and says not to use it for hard
# enforcement. Its documented failure direction is safe here -- "when Claude
# Code can't determine which commands the Bash input runs, it runs your hook
# regardless of the pattern" -- so uncertainty OVER-fires. The dangerous case is
# a DETERMINATE non-match, which is exactly what the TAB form was:
# `Bash(*npm *)` did not match a TAB-separated install although the parser did.
#
# Rules are shaped `Bash(*<tok>*)`, so the invariant that makes the gate sound
# is: anything the parser detects contains a manager name as a substring, hence
# some rule matches it. Assert it directly over the forms this guard cares
# about, so a future rule-shape change cannot quietly break it.
_rule_matches() {  # _rule_matches <command>
  local cmd="$1" r tok
  while IFS= read -r r; do
    r="${r%$'\r'}"; [[ -z "$r" ]] && continue
    tok="${r#Bash(\*}"; tok="${tok%%\*)}"; [[ -z "$tok" ]] && continue
    case "$cmd" in *"$tok"*) return 0 ;; esac
  done <<EOF
$rules
EOF
  return 1
}

# shellcheck source=../scripts/lib/parse-install-cmd.sh
source "$ROOT/scripts/lib/parse-install-cmd.sh"

GATE_FIXTURES="$ROOT/tests/fixtures/gate-invariant-commands.txt"
assert_file_exists "$GATE_FIXTURES" "gate-invariant fixture list present"
n_fixtures=0
while IFS= read -r _cmd; do
  _cmd="${_cmd%$'\r'}"
  [[ -z "$_cmd" || "$_cmd" == \#* ]] && continue
  n_fixtures=$((n_fixtures + 1))
  if [[ -z "$(parse_install_cmd "$_cmd")" ]]; then
    _fail "fixture is not detected by the parser, so it proves nothing: $_cmd"
    continue
  fi
  _rule_matches "$_cmd" || \
    _fail "parser detects an install the \`if\` rules would never spawn for: $_cmd"
done < "$GATE_FIXTURES"
# A truncated or renamed fixture file would make the loop vacuous.
if [[ "$n_fixtures" -lt 20 ]]; then
  _fail "only $n_fixtures gate-invariant fixtures were read (expected >=20)"
fi

# The handler count is documented for users running `plugin details`. Pin it to
# the number the docs actually state, so changing the rule set cannot silently
# make docs/e2e-checklist.md wrong.
doc_count=$(grep -oE 'reports \*\*[0-9]+\*\* hook handlers' "$ROOT/docs/e2e-checklist.md" | grep -oE '[0-9]+' | head -1)
real_count=$(jq '[.hooks[][].hooks[]] | length' "$HOOKS" | tr -d '\r')
if [[ -z "$doc_count" ]]; then
  _fail "could not read the documented handler count out of docs/e2e-checklist.md"
else
  assert_eq "$doc_count" "$real_count" "hooks.json handler count matches docs/e2e-checklist.md"
fi


finish_test
