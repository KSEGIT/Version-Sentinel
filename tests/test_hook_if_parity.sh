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
# KNOWN COUPLING — read before extending the parser. Measured on Claude Code
# 2.1.227, `Bash(npm *)` does NOT fire for a leading env assignment
# (`FOO=bar npm install x`) or a process wrapper (`timeout 30 npm install x`,
# `nice npm install x`), despite the hooks reference claiming both are stripped
# before rule matching. That costs nothing today because _parse_install_segment
# anchors on `^(npm|...)` and misses those forms too, so gated and ungated
# configs were verified to behave identically. But if the parser is ever taught
# to handle wrappers or leading assignments, the `if` rules must be widened in
# the same change — otherwise the parser fix passes its unit tests while the
# hook never spawns to run it.
#
# Command shapes measured end-to-end with the gate on and confirmed STILL
# BLOCKED: a pinned install behind a `cd ... &&` compound; the same install
# split across two lines by a bare newline rather than an operator; one behind
# `;`; one behind `||`; a pinned install written with doubled spaces; and a
# pinned pip3 install. Only the wrapper and leading-assignment forms above
# diverge, and there the parser misses them too.
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
branches=$(grep -cE '"\$seg"[[:space:]]+=~[[:space:]]+\^' "$PARSER" | tr -d ' ')
tokens=$(sed -nE "$EXTRACT" "$PARSER" | grep -c . | tr -d ' ')
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
done < <(sed -nE "$EXTRACT" "$PARSER")

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
      *"Bash($m *)"*) ;;
      *) _fail "$event is missing \`if\` rule 'Bash($m *)'" ;;
    esac
  done

  # hooks -> parser: no rule may name a manager the parser cannot handle.
  for r in $rules; do
    case "$r" in
      'Bash('*) ;;
      *) continue ;;
    esac
    mgr="${r#Bash(}"; mgr="${mgr%%\**}"; mgr="${mgr% }"
    case " $uniq_managers " in
      *" $mgr "*) ;;
      *) _fail "$event rule 'Bash($mgr *)' names a manager parse-install-cmd.sh does not recognize" ;;
    esac
  done

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

finish_test
