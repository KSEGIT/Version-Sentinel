#!/usr/bin/env bash
# Guards against an unquoted plugin-root placeholder in hook commands.
#
# Hosts substitute ${CLAUDE_PLUGIN_ROOT} (Claude Code, Codex) and
# ${extensionPath} (Gemini CLI) before the shell runs the command. Unquoted,
# an install path with a space (C:\Users\John Doe\...) splits into several
# words and bash cannot find the script, so the hook fails instead of
# guarding. `claude plugin validate` warns on this for the Claude file.
set -u
VS_TEST_NAME="hook-quoting"
source "$(dirname "$0")/assert.sh"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

checked=0
for f in hooks/hooks.json hooks/codex-hooks.json hooks/gemini-hooks.json; do
  path="$ROOT/$f"
  assert_file_exists "$path" "$f present"
  [[ -f "$path" ]] || continue
  while IFS= read -r cmd; do
    cmd="${cmd%$'\r'}"          # jq on Git Bash can emit CRLF
    [[ -n "$cmd" ]] || continue
    checked=$((checked + 1))
    case "$cmd" in
      *'${CLAUDE_PLUGIN_ROOT}'*|*'${extensionPath}'*)
        if [[ ! "$cmd" =~ \"\$\{(CLAUDE_PLUGIN_ROOT|extensionPath)\}[^\"]*\" ]]; then
          _fail "$f: plugin-root placeholder not inside double quotes: $cmd"
        fi
        ;;
      *)
        _fail "$f: command does not reference the plugin root: $cmd"
        ;;
    esac
  done < <(jq -r '.hooks[][].hooks[].command' "$path")
done

# A jq path change that matched nothing would make the loop vacuous.
if [[ "$checked" -eq 0 ]]; then
  _fail "no hook commands found; the check above ran on nothing"
fi

finish_test
