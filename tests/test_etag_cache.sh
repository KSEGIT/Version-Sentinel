#!/usr/bin/env bash
VS_TEST_NAME="etag-cache"
source "$(dirname "$0")/assert.sh"

source "$(dirname "$0")/../scripts/lib/etag-cache.sh"

VS_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$VS_TMPDIR"' EXIT

# --- etag_cache_dir creates directory ---
dir=$(etag_cache_dir "$VS_TMPDIR")
[[ -d "$dir" ]]
assert_eq "0" "$?" "cache dir created"

# --- etag_save stores etag and body ---
etag_save "$VS_TMPDIR" "https://example.com/pkg" '"abc123"' '{"version":"1.0"}'
assert_file_exists "$(etag_cache_dir "$VS_TMPDIR")/$(etag_key "https://example.com/pkg").etag" "etag file created"
assert_file_exists "$(etag_cache_dir "$VS_TMPDIR")/$(etag_key "https://example.com/pkg").body" "body file created"

# --- etag_get_tag retrieves stored etag ---
tag=$(etag_get_tag "$VS_TMPDIR" "https://example.com/pkg")
assert_eq '"abc123"' "$tag" "etag retrieved"

# --- etag_get_body retrieves stored body ---
body=$(etag_get_body "$VS_TMPDIR" "https://example.com/pkg")
assert_contains "$body" '{"version":"1.0"}' "body retrieved"

# --- etag_get_tag returns empty for unknown URL ---
tag=$(etag_get_tag "$VS_TMPDIR" "https://example.com/unknown")
assert_eq "" "$tag" "unknown URL → empty etag"

finish_test
