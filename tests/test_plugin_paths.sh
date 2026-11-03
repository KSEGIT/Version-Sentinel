#!/usr/bin/env bash
# Execute the shipped command instructions, not a reconstructed script path.
# An unquoted root, a stale script path, or lost arguments must fail this test.
set -u
VS_TEST_NAME="plugin-paths"
source "$(dirname "$0")/assert.sh"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VS_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$VS_TMPDIR"' EXIT
PLUGIN="$VS_TMPDIR/plugin with spaces"
PROJECT="$VS_TMPDIR/project with spaces"
mkdir -p "$PLUGIN" "$PROJECT"
source "$ROOT/tests/registry-fixture.sh"
registry_fixture_setup
cp -R "$ROOT/scripts" "$ROOT/commands" "$ROOT/platforms" "$ROOT/agents" "$PLUGIN/" || exit 1

read_command() {
  # Claude uses !bash, Gemini uses bash or !{bash ...}, and Kimi gives an
  # indented bash invocation. Keep the shipped shell text intact.
  tr -d '\r' < "$1" | sed -n \
    -e 's/^!\(bash .*\)$/\1/p' \
    -e t \
    -e 's/^[[:space:]]*\(bash .*\)$/\1/p' \
    -e t \
    -e 's/^[[:space:]]*!{\(bash .*\)}$/\1/p' \
    -e t \
    -e 's/.*`\(bash [^`]*\)`.*/\1/p' | tr -d '\r'
}

run_command() {
  local command="$1" arguments='npm path-fixture 1.0.0 "intentional: path fixture"'
  command="${command//\$\{extensionPath\}/$PLUGIN}"
  command="${command//\$ARGUMENTS/$arguments}"
  command="${command//\{\{args\}\}/$arguments}"
  (
    cd "$PROJECT" || exit 1
    export VS_DISABLE=0 CLAUDE_PLUGIN_ROOT="$PLUGIN" KIMI_PLUGIN_ROOT="$PLUGIN"
    bash -c "$command" path-test npm path-fixture 1.0.0 "intentional: path fixture"
  )
}

checked=0
for file in commands/vs-record.md commands/vs-record.toml platforms/kimi/commands/vs-record.md \
            commands/check-versions.md commands/check-versions.toml platforms/kimi/commands/check-versions.md \
            agents/version-reviewer.agent.md; do
  command=$(read_command "$PLUGIN/$file")
  if [[ -z "$command" || "$command" == *$'\n'* ]]; then
    _fail "$file: expected one executable command, got: $command"
    continue
  fi
  checked=$((checked + 1))
  rm -rf "$PROJECT/.version-sentinel"
  case "$file" in
    *vs-record*)
      rm -f "$PROJECT/package.json"
      output=$(run_command "$command" 2>&1)
      status=$?
      assert_exit_code 0 "$status" "$file records through the plugin path: $output"
      checks="$PROJECT/.version-sentinel/checks.json"
      assert_file_exists "$checks" "$file creates a recorded check"
      if [[ -f "$checks" ]]; then
        entry=$(jq -c '.entries | map({ecosystem,pkg,version,source})' "$checks" | tr -d '\r')
        assert_eq '[{"ecosystem":"npm","pkg":"path-fixture","version":"1.0.0","source":"intentional: path fixture"}]' \
          "$entry" "$file preserves all four arguments including the source with spaces"
      fi
      ;;
    *check-versions*|agents/*)
      # Even unpinned entries require successful upstream lookup. Only HTTP
      # is replaced by a fixture; command paths and the audit stay real.
      printf '%s\n' '{"dependencies":{"path-fixture":"*"}}' > "$PROJECT/package.json"
      output=$(run_command "$command" 2>&1)
      status=$?
      assert_exit_code 0 "$status" "$file audits through the plugin path: $output"
      row=$(printf '%s\n' "$output" | awk '$1 == "npm" && $2 == "path-fixture" {print $3, $4, $5}' | tr -d '\r')
      assert_eq '(unpinned) 4.17.21 UNPINNED' "$row" "$file reports the workspace dependency after online-fixture lookup"
      ;;
  esac
done
assert_eq 7 "$checked" "all Claude, Gemini and Kimi commands and the reviewer invocation were exercised"

finish_test
