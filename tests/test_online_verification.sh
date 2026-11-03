#!/usr/bin/env bash
VS_TEST_NAME=online-verification
TEST_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$TEST_DIR/.." && pwd)"
source "$TEST_DIR/assert.sh"
source "$TEST_DIR/registry-fixture.sh"
VS_TMPDIR=$(mktemp -d)
trap 'rm -rf "$VS_TMPDIR"' EXIT
registry_fixture_setup
mkdir "$VS_TMPDIR/project"
cd "$VS_TMPDIR/project" || exit 1

record() { bash "$ROOT/scripts/vs-record.sh" "$@" 2>&1; echo "exit=$?"; }
check() { bash "$ROOT/scripts/check-sidecar.sh" "$@" 2>&1; echo "exit=$?"; }

out=$(record npm lodash 4.17.21 https://fabricated.example/lodash)
assert_contains "$out" 'exit=1' 'fabricated source rejected'
out=$(record npm lodash 99.99.99 https://www.npmjs.com/package/lodash)
assert_contains "$out" 'exit=1' 'absent intended version rejected'
out=$(record npm lodash 4.17.20 https://www.npmjs.com/package/lodash)
assert_contains "$out" 'intentional:' 'older pin requires reason'
assert_contains "$out" 'exit=1' 'older pin without reason rejected'
out=$(record npm lodash 4.17.20 'intentional:   ')
assert_contains "$out" 'exit=1' 'empty intentional reason rejected'

out=$(record npm lodash 4.17.20 'intentional: compatibility test')
assert_contains "$out" 'exit=0' 'existing intentional older pin verified'
out=$(check npm lodash 4.17.20)
assert_contains "$out" 'exit=0' 'verified older pin authorizes exact version'
assert_eq true "$(jq -r '.entries[0].verification.online' .version-sentinel/checks.json)" 'online evidence stored'
assert_eq "$(pwd -P)" "$(jq -r '.entries[0].projectRoot' .version-sentinel/checks.json)" 'record bound to project'

# Failed online verification must not create or overwrite authorization.
cp .version-sentinel/checks.json "$VS_TMPDIR/original.json"
out=$(VS_FIXTURE_NETWORK_FAIL=1 record npm lodash 4.17.21 https://www.npmjs.com/package/lodash)
assert_contains "$out" 'exit=1' 'network failure rejects recording'
cmp -s .version-sentinel/checks.json "$VS_TMPDIR/original.json"
assert_eq 0 "$?" 'failed online check preserves prior record'

# Even an existing cache entry cannot convert an offline attempt into proof.
source "$ROOT/scripts/lib/etag-cache.sh"
etag_save "$PWD" https://registry.npmjs.org/lodash '"old"' '{"dist-tags":{"latest":"4.17.21"},"versions":{"4.17.21":{}}}'
out=$(VS_ETAG_DISABLE=0 VS_FIXTURE_NETWORK_FAIL=1 record npm lodash 4.17.21 https://www.npmjs.com/package/lodash)
assert_contains "$out" 'exit=1' 'stale cached upstream metadata cannot satisfy recording'
cmp -s .version-sentinel/checks.json "$VS_TMPDIR/original.json"
assert_eq 0 "$?" 'stale-cache failure creates no new evidence'

out=$(record npm lodash 4.17.21 https://www.npmjs.com/package/lodash)
assert_contains "$out" 'exit=0' 'latest exact version recorded'
out=$(check npm lodash 4.17.21)
assert_contains "$out" 'exit=0' 'fresh verified record permits exact version'

cp .version-sentinel/checks.json "$VS_TMPDIR/verified.json"
jq '.entries[0].projectRoot="/different/project"' "$VS_TMPDIR/verified.json" > .version-sentinel/checks.json
assert_contains "$(check npm lodash 4.17.21)" 'exit=2' 'wrong project rejected'
jq 'del(.entries[0].verification)' "$VS_TMPDIR/verified.json" > .version-sentinel/checks.json
assert_contains "$(check npm lodash 4.17.21)" 'exit=2' 'legacy URL-only record rejected'
jq '.entries[0].source="auto-recorded: post-install"' "$VS_TMPDIR/verified.json" > .version-sentinel/checks.json
assert_contains "$(check npm lodash 4.17.21)" 'exit=2' 'post-install source rejected'
jq '.entries[0].source="https://fabricated.example/lodash"' "$VS_TMPDIR/verified.json" > .version-sentinel/checks.json
assert_contains "$(check npm lodash 4.17.21)" 'exit=2' 'fabricated source on structured record rejected'
jq '.entries[0].checkedAt="2000-01-01T00:00:00Z" | .entries[0].verification.verifiedAt="2000-01-01T00:00:00Z"' "$VS_TMPDIR/verified.json" > .version-sentinel/checks.json
assert_contains "$(check npm lodash 4.17.21)" 'exit=2' 'expired evidence rejected'
jq '.entries[0].verification.verifiedAt="2999-01-01T00:00:00Z"' "$VS_TMPDIR/verified.json" > .version-sentinel/checks.json
assert_contains "$(check npm lodash 4.17.21)" 'exit=2' 'future evidence rejected'

for spec in 'pip requests 2.31.0 https://pypi.org/project/requests/' 'cargo serde 1.0.196 https://crates.io/crates/serde' 'csproj Newtonsoft.Json 13.0.3 https://www.nuget.org/packages/Newtonsoft.Json'; do
  read -r eco pkg ver source_url <<< "$spec"
  assert_contains "$(record "$eco" "$pkg" "$ver" "$source_url")" 'exit=0' "online existence check for $eco"
  assert_contains "$(check "$eco" "$pkg" "$ver")" 'exit=0' "verified record for $eco"
done
finish_test
