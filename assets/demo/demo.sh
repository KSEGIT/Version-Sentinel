#!/usr/bin/env bash
# Version Sentinel demo — recorded with asciinema, converted with agg.
# Runs the real hook scripts from this repo against a throwaway project dir.
set -u

VS="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

DIM=$'\033[2m'; RED=$'\033[31m'; GRN=$'\033[32m'; CYN=$'\033[36m'; BOLD=$'\033[1m'; RST=$'\033[0m'

DEMO_DIR="$(mktemp -d)/my-app"
mkdir -p "$DEMO_DIR"
cd "$DEMO_DIR" || exit 1

echo '{"tool_name":"Bash","tool_input":{"command":"npm install lodash@4.17.21"}}' > .attempt-stale.json

note() { printf '\n%s# %s%s\n' "$DIM" "$1" "$RST"; sleep "${2:-1.6}"; }

type_run() { # $1 = command shown on screen, $2 = command actually run (defaults to $1)
  local disp="$1" real="${2:-$1}" i
  printf '%s$ %s' "$CYN" "$RST"
  for ((i = 0; i < ${#disp}; i++)); do printf '%s' "${disp:i:1}"; sleep 0.03; done
  printf '\n'
  eval "$real"
  sleep 0.6
}

clear
printf '%s%s  VERSION SENTINEL — demo%s\n' "$BOLD" "$GRN" "$RST"
printf '%s  every dependency is checked against its registry before it lands%s\n' "$DIM" "$RST"
sleep 2.5

note "Claude Code is working in ./my-app and decides it needs lodash."
note "From training data, it remembers lodash@4.17.21 — the version every LLM knows."
note "The PreToolUse hook intercepts the install before it runs:"
type_run 'echo {... "npm install lodash@4.17.21" ...} | detect-install-cmd.sh' \
  'cat .attempt-stale.json | bash "$VS/scripts/detect-install-cmd.sh"; printf "\033[31mexit code: %s — the install never ran\033[0m\n" "$?"'
sleep 1.5

note "Claude must look up the real latest version first:"
type_run 'curl -s https://registry.npmjs.org/lodash/latest | jq -r .version'
LATEST="$(curl -s --max-time 8 https://registry.npmjs.org/lodash/latest | jq -r .version)"
LATEST="${LATEST:-4.18.1}"
sleep 1.2

note "...and record where it checked:"
type_run "vs-record.sh npm lodash $LATEST https://www.npmjs.com/package/lodash" \
  'bash "$VS/scripts/vs-record.sh" npm lodash "'"$LATEST"'" https://www.npmjs.com/package/lodash'
sleep 1.2

echo "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"npm install lodash@$LATEST\"}}" > .attempt-verified.json
note "Retry — this time with the verified version:"
type_run "echo {... \"npm install lodash@$LATEST\" ...} | detect-install-cmd.sh" \
  'cat .attempt-verified.json | bash "$VS/scripts/detect-install-cmd.sh"; printf "\033[32mexit code: %s — install proceeds\033[0m\n" "$?"'
type_run "npm install lodash@$LATEST" \
  'printf "added 1 package in 612ms\n\033[32m+ lodash@%s\033[0m\n" "'"$LATEST"'"'
sleep 1.2

note "The stale version from training data stays blocked:"
type_run 'echo {... "npm install lodash@4.17.21" ...} | detect-install-cmd.sh' \
  'cat .attempt-stale.json | bash "$VS/scripts/detect-install-cmd.sh" >/dev/null 2>&1; printf "\033[31mexit code: %s — still blocked (no check on record for 4.17.21)\033[0m\n" "$?"'
sleep 1.5

printf '\n%s%s  Version Sentinel%s %s— no dependency ships unverified%s\n' "$BOLD" "$GRN" "$RST" "$DIM" "$RST"
printf '%s  npm · PyPI · Cargo · NuGet  —  Claude Code · Kimi · Gemini CLI · Codex%s\n' "$DIM" "$RST"
printf '%s  github.com/KSEGIT/Version-Sentinel%s\n' "$BOLD" "$RST"
sleep 3

cd /
rm -rf "$(dirname "$DEMO_DIR")"
