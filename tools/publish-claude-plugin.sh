#!/usr/bin/env bash
# Publish a built package without changing the source checkout or its index.
set -euo pipefail

if [[ "$#" -lt 1 || "$#" -gt 2 ]]; then
  echo 'Usage: bash tools/publish-claude-plugin.sh PACKAGE_DIRECTORY [REMOTE_NAME]' >&2
  exit 1
fi
bundle="$1"
remote="${2:-origin}"
branch='refs/heads/claude-directory'
if [[ ! "$remote" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]; then
  echo 'Use a configured Git remote name, not a URL or path.' >&2
  exit 1
fi
if [[ ! -d "$bundle" || ! -f "$bundle/.claude-plugin/plugin.json" || ! -f "$bundle/README.md" ]]; then
  echo 'The package must contain .claude-plugin/plugin.json and README.md.' >&2
  exit 1
fi
bundle=$(cd "$bundle" && pwd -P)
git_dir=$(git rev-parse --absolute-git-dir)
source_commit=$(git rev-parse --verify HEAD)
if ! git remote get-url "$remote" >/dev/null 2>&1; then
  echo 'The configured Git remote does not exist.' >&2
  exit 1
fi

temporary=$(mktemp -d)
trap 'rm -rf "$temporary"' EXIT
# Avoid importing another Git checkout, even when handed the wrong package path.
if [[ -n "$(find "$bundle" -name .git -print -quit)" ]]; then
  echo 'The package must not contain Git metadata.' >&2
  exit 1
fi

if ! remote_ref=$(git ls-remote --heads "$remote" "$branch" 2>"$temporary/git-error"); then
  echo 'Cannot read the Claude directory publication branch; nothing was published.' >&2
  exit 1
fi
parent=''
if [[ -n "$remote_ref" ]]; then
  if ! git fetch --quiet --no-tags "$remote" "$branch" 2>"$temporary/git-error"; then
    echo 'Cannot fetch the Claude directory publication branch; nothing was published.' >&2
    exit 1
  fi
  parent=$(git rev-parse --verify FETCH_HEAD)
fi

bundle_git() {
  GIT_INDEX_FILE="$temporary/index" git -C "$bundle" --git-dir="$git_dir" --work-tree="$bundle" "$@"
}
bundle_git read-tree --empty
# The builder already chose the package files. User/global ignore patterns
# must not silently remove a required manifest, README, or runtime file.
bundle_git add --force --all -- .
tree=$(bundle_git write-tree)
if [[ -n "$parent" && "$tree" == "$(git rev-parse "$parent^{tree}")" ]]; then
  echo 'Claude directory package is already current.'
  exit 0
fi

# Bash 3.2 treats an empty array as unset under nounset.
if [[ -n "$parent" ]]; then
  commit=$(printf 'build: Claude directory package from %s\n' "$source_commit" | git commit-tree "$tree" -p "$parent")
else
  commit=$(printf 'build: Claude directory package from %s\n' "$source_commit" | git commit-tree "$tree")
fi
# Deliberately omit --force: a concurrent publisher must fail instead of
# discarding a version another process has just published.
if ! git push --quiet "$remote" "$commit:$branch" 2>"$temporary/git-error"; then
  echo 'Claude directory push failed; check connectivity, permissions, and concurrent publication.' >&2
  exit 1
fi
echo "Published Claude directory package from $source_commit."
