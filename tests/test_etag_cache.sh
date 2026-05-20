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

# --- curl_with_etag integration tests (stub-driven) ---

STUB_DIR="$(mktemp -d)"
CURL_TMPDIR="$(mktemp -d)"
# Append to EXIT trap
trap 'rm -rf "$VS_TMPDIR" "$STUB_DIR" "$CURL_TMPDIR"' EXIT

cat > "$STUB_DIR/curl" <<'STUB'
#!/usr/bin/env bash
# Stub curl for curl_with_etag. Parses -D, -o, -w, -H args.
headers_file="" body_file="" has_http_code=0
prev=""
for arg in "$@"; do
  case "$prev" in
    -D) headers_file="$arg" ;;
    -o) body_file="$arg" ;;
    -H) ;; # consumed
    -w) ;; # skip format string
  esac
  case "$arg" in
    -w) has_http_code=1 ;;
  esac
  prev="$arg"
done

case "${STUB_MODE:-200}" in
  200)
    [[ -n "$headers_file" ]] && printf 'HTTP/1.1 200 OK\r\nETag: "tag-v1"\r\n\r\n' > "$headers_file"
    if [[ -n "$body_file" ]]; then
      printf '{"result":"fresh"}' > "$body_file"
      [[ "$has_http_code" -eq 1 ]] && printf '200'
    else
      printf '{"result":"fresh"}'
    fi
    ;;
  304)
    [[ -n "$headers_file" ]] && printf 'HTTP/1.1 304 Not Modified\r\n\r\n' > "$headers_file"
    [[ -n "$body_file" ]] && : > "$body_file"
    [[ "$has_http_code" -eq 1 ]] && printf '304'
    ;;
  fail)
    exit 1
    ;;
esac
STUB
chmod +x "$STUB_DIR/curl"

_ORIG_PATH="$PATH"
export PATH="$STUB_DIR:$PATH"

# Test: 200 response — body returned and ETag cached
STUB_MODE=200 body=$(curl_with_etag "$CURL_TMPDIR" "https://example.com/api")
assert_eq '{"result":"fresh"}' "$body" "200: correct body returned"
cached_tag=$(etag_get_tag "$CURL_TMPDIR" "https://example.com/api")
assert_eq '"tag-v1"' "$cached_tag" "200: ETag cached after 200"

# Test: 304 response — cached body returned (ETag was saved from 200 above)
STUB_MODE=304 body=$(curl_with_etag "$CURL_TMPDIR" "https://example.com/api")
assert_eq '{"result":"fresh"}' "$body" "304: cached body returned on Not Modified"

# Test: network failure — fallback to cached body
STUB_MODE=fail body=$(curl_with_etag "$CURL_TMPDIR" "https://example.com/api" 2>/dev/null)
assert_eq '{"result":"fresh"}' "$body" "fail: falls back to cached body on network error"

# Test: network failure with no cache → exit 1
CURL_NOCACHE_DIR="$(mktemp -d)"
STUB_MODE=fail curl_with_etag "$CURL_NOCACHE_DIR" "https://example.com/api" >/dev/null 2>&1
assert_eq "1" "$?" "fail: exits 1 when no cached body exists"
rm -rf "$CURL_NOCACHE_DIR"

# Test: VS_ETAG_DISABLE bypass — curl called directly, no ETag headers, no caching
CURL_DISABLE_DIR="$(mktemp -d)"
STUB_MODE=200 VS_ETAG_DISABLE=1 body=$(curl_with_etag "$CURL_DISABLE_DIR" "https://example.com/api")
assert_eq '{"result":"fresh"}' "$body" "VS_ETAG_DISABLE: body returned directly"
no_tag=$(etag_get_tag "$CURL_DISABLE_DIR" "https://example.com/api")
assert_eq "" "$no_tag" "VS_ETAG_DISABLE: nothing cached"
rm -rf "$CURL_DISABLE_DIR"

export PATH="$_ORIG_PATH"

finish_test
