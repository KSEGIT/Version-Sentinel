#!/usr/bin/env bash
# ETag-based HTTP cache for registry responses.
# Cache dir: <base>/.version-sentinel/.etag-cache/

etag_cache_dir() {
  local base="${1:-$PWD}"
  local dir="$base/.version-sentinel/.etag-cache"
  mkdir -p "$dir"
  echo "$dir"
}

etag_key() {
  local url="$1"
  printf '%s' "$url" | python3 -c "import sys,hashlib;print(hashlib.md5(sys.stdin.buffer.read()).hexdigest())"
}

etag_save() {
  local base="$1" url="$2" etag="$3" body="$4"
  local dir key
  dir=$(etag_cache_dir "$base")
  key=$(etag_key "$url")
  printf '%s' "$etag" > "$dir/${key}.etag"
  printf '%s' "$body" > "$dir/${key}.body"
}

etag_get_tag() {
  local base="$1" url="$2"
  local dir key
  dir=$(etag_cache_dir "$base")
  key=$(etag_key "$url")
  [[ -f "$dir/${key}.etag" ]] && cat "$dir/${key}.etag"
}

etag_get_body() {
  local base="$1" url="$2"
  local dir key
  dir=$(etag_cache_dir "$base")
  key=$(etag_key "$url")
  [[ -f "$dir/${key}.body" ]] && cat "$dir/${key}.body"
}

# curl_with_etag <base_dir> <url> [extra_curl_args...]
# Returns body (from cache on 304, from response on 200). Exit 1 on failure.
curl_with_etag() {
  local base="$1" url="$2"
  shift 2
  # Bypass ETag when disabled (e.g., tests with curl stubs)
  if [[ "${VS_ETAG_DISABLE:-0}" == "1" ]]; then
    curl -fsSL "$@" "$url"
    return $?
  fi

  local etag headers_file body_file
  etag=$(etag_get_tag "$base" "$url")
  headers_file=$(mktemp)
  body_file=$(mktemp)
  trap 'rm -f "$headers_file" "$body_file"' RETURN

  local curl_args=(-sSL -D "$headers_file" -o "$body_file" "$@")
  if [[ -n "$etag" ]]; then
    curl_args+=(-H "If-None-Match: $etag")
  fi
  curl_args+=("$url")

  local http_code
  http_code=$(curl -w '%{http_code}' "${curl_args[@]}" 2>/dev/null) || {
    local cached
    cached=$(etag_get_body "$base" "$url")
    if [[ -n "$cached" ]]; then
      echo "$cached"
      return 0
    fi
    return 1
  }

  if [[ "$http_code" == "304" ]]; then
    etag_get_body "$base" "$url"
    return 0
  fi

  local new_body new_etag
  new_body=$(cat "$body_file")
  new_etag=$(grep -i '^etag:' "$headers_file" | head -1 | sed 's/^[^:]*: *//' | tr -d '\r')
  if [[ -n "$new_etag" ]]; then
    etag_save "$base" "$url" "$new_etag" "$new_body"
  fi
  echo "$new_body"
  return 0
}
