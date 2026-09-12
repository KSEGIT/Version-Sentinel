#!/usr/bin/env bash
VS_TEST_NAME="parse-npm"
FIXTURES="$(dirname "$0")/fixtures"
source "$(dirname "$0")/assert.sh"
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "$SCRIPT_DIR/scripts/lib/parse-manifest.sh"

out=$(parse_npm "$FIXTURES/package.json" | sort)
expected=$(printf '%s\n' \
  "lodash	4.17.21" \
  "express	4.19.2" \
  "jest	29.7.0" \
  "react	18.0.0" \
  "fsevents	2.3.3" | sort)
assert_eq "$expected" "$out" "npm all 4 dep sections parsed, version prefixes stripped"

tmp=$(mktemp)
printf '%s\n' '{"dependencies":{"a":"latest","b":"next","c":"*","d":"","local":"file:../local","work":"workspace:*","link":"link:../local","git":"git+https://example.com/repo.git","github":"user/repo","url":"https://example.com/pkg.tgz"}}' > "$tmp"
out=$(parse_npm "$tmp" | sort)
expected=$(printf '%s\n' \
  $'a\t__version_sentinel_unpinned__' \
  $'b\t__version_sentinel_unpinned__' \
  $'c\t__version_sentinel_unpinned__' \
  $'d\t__version_sentinel_unpinned__' | sort)
assert_eq "$expected" "$out" "npm tags and missing versions are unpinned; local/workspace refs skipped"
rm -f "$tmp"

tmp=$(mktemp)
printf '%s\n' '{"dependencies":{"major-x":"1.x","major-X":"1.X","major-star":"1.*","partial-major":"1","partial-minor":"1.2","compound":"1.x || 2.x","partial-union":"1.2 || 2.3.4","partial-hyphen":"1.2 - 2.3.4","exact-union":"1.2.3 || 2.3.4","exact-hyphen":"1.2.3 - 2.3.4","bounded":">=1.x <2","scoped-alias":"npm:@scope/pkg@1.2"}}' > "$tmp"
out=$(parse_npm "$tmp" | sort)
expected=$(printf '%s\n' \
  $'bounded\t__version_sentinel_unpinned__' \
  $'compound\t__version_sentinel_unpinned__' \
  $'exact-hyphen\t__version_sentinel_unpinned__' \
  $'exact-union\t__version_sentinel_unpinned__' \
  $'major-X\t__version_sentinel_unpinned__' \
  $'major-star\t__version_sentinel_unpinned__' \
  $'major-x\t__version_sentinel_unpinned__' \
  $'partial-major\t__version_sentinel_unpinned__' \
  $'partial-minor\t__version_sentinel_unpinned__' \
  $'partial-union\t__version_sentinel_unpinned__' \
  $'partial-hyphen\t__version_sentinel_unpinned__' \
  $'@scope/pkg\t__version_sentinel_unpinned__' | sort)
assert_eq "$expected" "$out" "all npm wildcard selector forms are unpinned"
rm -f "$tmp"

tmp=$(mktemp)
printf '%s\n' '{"dependencies":{"compat":"npm:lodash","scoped-bare":"npm:@scope/bare","scoped":"npm:@scope/pkg@1.2.3","lodash":"*"},"devDependencies":{"lodash":"4.17.21"}}' > "$tmp"
out=$(parse_npm "$tmp" | sort)
expected=$(printf '%s\n' \
  $'@scope/pkg\t1.2.3' \
  $'@scope/bare\t__version_sentinel_unpinned__' \
  $'lodash\t4.17.21' \
  $'lodash\t__version_sentinel_unpinned__' \
  $'lodash\t__version_sentinel_unpinned__' | sort)
assert_eq "$expected" "$out" "npm aliases use real targets and duplicate section entries are preserved"
rm -f "$tmp"

# jq emits CRLF on Git Bash. The parser must normalize the record before it
# classifies an npm alias.
out=$(_emit_npm_manifest_dependency "compat" $'npm:lodash\r')
assert_eq $'lodash\t__version_sentinel_unpinned__' "$out" "npm alias with CRLF record"

# Empty manifest → empty output, exit 0
out=$(parse_npm "$FIXTURES/package_no_deps.json")
assert_eq "" "$out" "no deps → empty"

# Missing file → empty output, exit 0 (fail-open)
out=$(parse_npm /nope/nonexistent.json 2>/dev/null)
assert_eq "" "$out" "missing file → empty (fail open)"

finish_test
