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
managers=()
while read -r tok; do
  [[ -z "$tok" ]] && continue
  tok="${tok#(}"; tok="${tok%)}"
  IFS='|' read -r -a alts <<< "$tok"
  for alt in "${alts[@]}"; do
    if [[ "$alt" == *'?' ]]; then
      base="${alt%\?}"          # pip3?  -> pip3
      managers+=("$base" "${base%?}")   # ...and the optional-char form: pip
    else
      managers+=("$alt")
    fi
  done
done < <(sed -nE 's/.*=~[[:space:]]+\^(\(?[A-Za-z0-9|?]+\)?)\[\[:space:\]\].*/\1/p' "$PARSER")

# Dedupe while preserving order.
uniq_managers=()
for m in "${managers[@]}"; do
  seen=0
  for u in "${uniq_managers[@]:-}"; do [[ "$u" == "$m" ]] && seen=1 && break; done
  [[ "$seen" -eq 0 ]] && uniq_managers+=("$m")
done

# A sed that quietly matches nothing would make every assertion below vacuous,
# so pin both the count and a few names we know the parser handles.
if [[ "${#uniq_managers[@]}" -lt 8 ]]; then
  _fail "extracted only ${#uniq_managers[@]} managers from $PARSER (expected >=8): ${uniq_managers[*]:-<none>}"
fi
for expected in npm pnpm yarn bun pip pip3 poetry uv cargo dotnet; do
  found=0
  for m in "${uniq_managers[@]:-}"; do [[ "$m" == "$expected" ]] && found=1 && break; done
  assert_eq "1" "$found" "parser extraction found '$expected'"
done

# --- Every Bash hook handler is gated, and covers every manager -------------
for event in PreToolUse PostToolUse; do
  mapfile -t rules < <(jq -r --arg ev "$event" \
    '.hooks[$ev][]? | select(.matcher == "Bash") | .hooks[] | (.if // "<UNGATED>")' "$HOOKS")

  if [[ "${#rules[@]}" -eq 0 ]]; then
    _fail "$event: no Bash hook group found in hooks.json"
    continue
  fi

  for r in "${rules[@]}"; do
    [[ "$r" == "<UNGATED>" ]] && _fail "$event: a Bash handler has no \`if\` rule; it would spawn on every Bash call"
  done

  # Parser -> hooks: no manager may be missing a rule (missing == silent bypass).
  for m in "${uniq_managers[@]:-}"; do
    want="Bash($m *)"
    found=0
    for r in "${rules[@]}"; do [[ "$r" == "$want" ]] && found=1 && break; done
    assert_eq "1" "$found" "$event has \`if\` rule '$want'"
  done

  # hooks -> parser: no rule may name a manager the parser cannot handle.
  for r in "${rules[@]}"; do
    [[ "$r" == "<UNGATED>" ]] && continue
    mgr="${r#Bash(}"; mgr="${mgr%% \*)}"
    found=0
    for m in "${uniq_managers[@]:-}"; do [[ "$m" == "$mgr" ]] && found=1 && break; done
    assert_eq "1" "$found" "$event rule '$r' names a manager parse-install-cmd.sh recognizes"
  done
done

# --- The manifest-edit hook is deliberately NOT gated ----------------------
# Edit/Write/MultiEdit are a small share of tool calls, and `if` matches the
# literal tool name (an Edit(...) rule does not fire for the Write tool), so
# gating that group buys little and risks a manifest pattern silently going
# unguarded. Keep it firing on everything.
ungated=$(jq '[.hooks.PreToolUse[]? | select(.matcher != "Bash") | .hooks[] | select(has("if"))] | length' "$HOOKS")
assert_eq "0" "$ungated" "manifest-edit hook stays ungated on purpose"

finish_test
