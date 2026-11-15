#!/usr/bin/env bash
# Exercise publication against a local bare repository; never use GitHub.
set -u
VS_TEST_NAME="claude-publish"
source "$(dirname "$0")/assert.sh"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VS_TMPDIR=$(mktemp -d)
trap 'rm -rf "$VS_TMPDIR"' EXIT
REMOTE="$VS_TMPDIR/remote.git"
SOURCE="$VS_TMPDIR/source"
BUNDLE="$VS_TMPDIR/package with spaces"
git init --bare -q "$REMOTE" || exit 1
git init -q "$SOURCE" || exit 1
git -C "$SOURCE" checkout -qb main || exit 1
git -C "$SOURCE" config user.name 'Publication test'
git -C "$SOURCE" config user.email 'publication@example.invalid'
# Packaging must not inherit the developer's global ignore patterns.
printf 'README.md\n' > "$VS_TMPDIR/global-ignore"
git -C "$SOURCE" config core.excludesFile "$VS_TMPDIR/global-ignore"
printf 'source only\n' > "$SOURCE/source.txt"
git -C "$SOURCE" add .
git -C "$SOURCE" commit -qm 'source baseline' || exit 1
git -C "$SOURCE" remote add origin "$REMOTE"
git -C "$SOURCE" push -q origin main || exit 1
mkdir -p "$BUNDLE/.claude-plugin" "$BUNDLE/scripts"
printf '{"name":"fixture","version":"1.0.0"}\n' > "$BUNDLE/.claude-plugin/plugin.json"
printf 'Fixture package\n' > "$BUNDLE/README.md"
printf '#!/usr/bin/env bash\nprintf ready\n' > "$BUNDLE/scripts/run.sh"
chmod +x "$BUNDLE/scripts/run.sh"
# Observe the mode Git can represent on this filesystem. Windows checkouts do
# not necessarily support chmod's executable bit.
MODE_PROBE="$VS_TMPDIR/mode-probe"
git init -q "$MODE_PROBE"
cp -p "$BUNDLE/scripts/run.sh" "$MODE_PROBE/run.sh"
git -C "$MODE_PROBE" add run.sh
expected_mode=$(git -C "$MODE_PROBE" ls-files --stage run.sh | awk '{print $1}')

# Publication must leave staged and unstaged source work untouched.
printf 'staged change\n' > "$SOURCE/source.txt"
git -C "$SOURCE" add source.txt
printf 'unstaged change\n' >> "$SOURCE/source.txt"
before_status=$(git -C "$SOURCE" status --porcelain)
before_index=$(git -C "$SOURCE" write-tree)
before_head=$(git -C "$SOURCE" rev-parse HEAD)
before_main=$(git --git-dir="$REMOTE" rev-parse refs/heads/main)

publish() {
  (cd "$SOURCE" && bash "$ROOT/tools/publish-claude-plugin.sh" "$BUNDLE")
}

output=$(publish 2>&1)
status=$?
assert_exit_code 0 "$status" "initial publication succeeds: $output"
if [[ "$status" -ne 0 ]]; then
  finish_test
  exit 1
fi
first=$(git --git-dir="$REMOTE" rev-parse refs/heads/claude-directory)
files=$(git --git-dir="$REMOTE" ls-tree -r --name-only "$first")
assert_eq $'.claude-plugin/plugin.json\nREADME.md\nscripts/run.sh' "$files" "published tree contains bundle only"
assert_eq 1 "$(git --git-dir="$REMOTE" rev-list --count "$first")" "initial commit has no source history"
assert_eq "$expected_mode" "$(git --git-dir="$REMOTE" ls-tree "$first" scripts/run.sh | awk '{print $1}')" "Git's observed file mode is preserved"

output=$(publish 2>&1)
assert_exit_code 0 "$?" "unchanged bundle succeeds: $output"
assert_eq "$first" "$(git --git-dir="$REMOTE" rev-parse refs/heads/claude-directory)" "unchanged bundle makes no commit"

printf 'Updated package\n' > "$BUNDLE/README.md"
rm "$BUNDLE/scripts/run.sh"
output=$(publish 2>&1)
assert_exit_code 0 "$?" "changed bundle publishes: $output"
second=$(git --git-dir="$REMOTE" rev-parse refs/heads/claude-directory)
assert_eq "$first" "$(git --git-dir="$REMOTE" rev-parse "$second^")" "update preserves publication parent"
assert_eq 'Updated package' "$(git --git-dir="$REMOTE" show "$second:README.md")" "updated file is published"
assert_eq $'.claude-plugin/plugin.json\nREADME.md' "$(git --git-dir="$REMOTE" ls-tree -r --name-only "$second")" "removed files do not survive update"
assert_eq "$before_main" "$(git --git-dir="$REMOTE" rev-parse refs/heads/main)" "remote main is unchanged"
assert_eq main "$(git -C "$SOURCE" branch --show-current)" "current branch is unchanged"
assert_eq "$before_head" "$(git -C "$SOURCE" rev-parse HEAD)" "source commit is unchanged"
assert_eq "$before_index" "$(git -C "$SOURCE" write-tree)" "source index is unchanged"
assert_eq "$before_status" "$(git -C "$SOURCE" status --porcelain)" "source worktree is unchanged"

output=$(cd "$SOURCE" && bash "$ROOT/tools/publish-claude-plugin.sh" "$BUNDLE" "$VS_TMPDIR/missing.git" 2>&1)
[[ "$?" -ne 0 ]] || _fail "arbitrary remote URL/path must be rejected"
output=$(cd "$SOURCE" && bash "$ROOT/tools/publish-claude-plugin.sh" "$BUNDLE" origin main 2>&1)
[[ "$?" -ne 0 ]] || _fail "arbitrary branch target must be rejected"

git -C "$SOURCE" remote set-url origin "$VS_TMPDIR/missing.git"
output=$(publish 2>&1)
[[ "$?" -ne 0 ]] || _fail "remote lookup failure must stop publication"
[[ "$output" != *"$VS_TMPDIR/missing.git"* ]] || _fail "failure must not print remote URL"

finish_test
