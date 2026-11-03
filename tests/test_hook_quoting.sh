#!/usr/bin/env bash
# Run the configured hooks from a real plugin copy whose path contains spaces.
# Removing quotes from any root expansion must break the hook's behavior.
set -u
VS_TEST_NAME="hook-quoting"
source "$(dirname "$0")/assert.sh"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VS_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$VS_TMPDIR"' EXIT
PLUGIN="$VS_TMPDIR/plugin with spaces"
PROJECT="$VS_TMPDIR/project with spaces"
mkdir -p "$PLUGIN" "$PROJECT"
source "$ROOT/tests/registry-fixture.sh"
registry_fixture_setup
cp -R "$ROOT/scripts" "$ROOT/hooks" "$PLUGIN/" || exit 1

manifest_input=$(jq -nc --arg path "$PROJECT/package.json" \
  '{tool_name:"Write",tool_input:{file_path:$path,content:"{\"dependencies\":{\"path-fixture\":\"1.0.0\"}}"}}')
install_input='{"tool_name":"Bash","tool_input":{"command":"npm install path-fixture@1.0.0"}}'
post_input='{"tool_name":"Bash","tool_input":{"command":"npm install path-fixture@1.0.0"},"tool_response":{"exit_code":0}}'

run_hook() {
  local command="$1" input="$2" separator='/'
  # Gemini resolves these placeholders before invoking the shell. Claude and
  # Codex can expand CLAUDE_PLUGIN_ROOT in the shell environment.
  command="${command//\$\{extensionPath\}/$PLUGIN}"
  command="${command//\$\{\/\}/$separator}"
  (
    cd "$PROJECT" || exit 1
    export VS_DISABLE=0 CLAUDE_PLUGIN_ROOT="$PLUGIN"
    printf '%s\n' "$input" | bash -c "$command"
  )
}

assert_record() {
  local source="$1" label="$2" value
  assert_file_exists "$PROJECT/.version-sentinel/checks.json" "$label"
  [[ -f "$PROJECT/.version-sentinel/checks.json" ]] || return
  value=$(jq -c '.entries | map({ecosystem,pkg,version,source})' \
    "$PROJECT/.version-sentinel/checks.json" | tr -d '\r')
  assert_eq "[{\"ecosystem\":\"npm\",\"pkg\":\"path-fixture\",\"version\":\"1.0.0\",\"source\":\"$source\"}]" \
    "$value" "$label preserves package, version and source"
}

for file in hooks/hooks.json hooks/codex-hooks.json hooks/gemini-hooks.json; do
  commands=$(jq -r '[.hooks[][].hooks[].command] | unique[]' "$PLUGIN/$file" | tr -d '\r')
  checked=0
  while IFS= read -r command; do
    command="${command%$'\r'}" # Git Bash tool output can be CRLF.
    [[ -n "$command" ]] || continue
    checked=$((checked + 1))
    rm -rf "$PROJECT/.version-sentinel"
    printf '{"dependencies":{}}\n' > "$PROJECT/package.json"
    case "$command" in
      *session-start.sh*)
        output=$(run_hook "$command" '{}' 2>&1)
        status=$?
        assert_exit_code 0 "$status" "$file starts the session from a spaced path: $output"
        ;;
      *detect-manifest-edit.sh*|*detect-install-cmd.sh*)
        (cd "$PROJECT" && bash "$PLUGIN/scripts/check-versions.sh") >/dev/null || exit 1
        case "$command" in
          *detect-manifest-edit.sh*) input="$manifest_input" ;;
          *) input="$install_input" ;;
        esac
        # The exit code distinguishes a real dependency block from a shell
        # error caused by a split path (usually exit 127).
        output=$(run_hook "$command" "$input" 2>&1)
        status=$?
        assert_exit_code 2 "$status" "$file blocks unchecked dependency from a spaced path: $output"
        (
          cd "$PROJECT" || exit 1
          bash "$PLUGIN/scripts/vs-record.sh" npm path-fixture 1.0.0 "intentional: path fixture"
        ) >/dev/null 2>&1
        assert_exit_code 0 "$?" "$file records fixture check"
        assert_record "intentional: path fixture" "$file fixture check"
        output=$(run_hook "$command" "$input" 2>&1)
        status=$?
        assert_exit_code 0 "$status" "$file allows dependency after a recorded check: $output"
        ;;
      *auto-record.sh*)
        output=$(run_hook "$command" "$post_input" 2>&1)
        status=$?
        assert_exit_code 0 "$status" "$file post-install hook succeeds from a spaced path: $output"
        if [[ -f "$PROJECT/.version-sentinel/checks.json" ]]; then
          _fail "$file post-install hook must never create version authorization"
        fi
        ;;
      *) _fail "$file: no behavioral case for configured hook: $command" ;;
    esac
  done <<EOF
$commands
EOF
  # Do not pass if JSON extraction silently skipped the hooks.
  if [[ "$checked" -lt 4 ]]; then
    _fail "$file: exercised only $checked configured commands; expected at least four"
  fi
done

finish_test
