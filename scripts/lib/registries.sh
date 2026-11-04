#!/usr/bin/env bash
# registry_latest <ecosystem> <pkg> → prints latest version string, exit 0
# Exits 1 on failure.

_REGISTRIES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=json.sh
source "$_REGISTRIES_DIR/json.sh"
if [[ -z "${_VS_RETRY_LOADED:-}" ]]; then
  if source "$_REGISTRIES_DIR/retry.sh"; then
    _VS_RETRY_LOADED=1
  else
    echo "version-sentinel: failed to source retry.sh" >&2
    return 1
  fi
fi

if [[ -z "${_VS_ETAG_LOADED:-}" ]]; then
  if source "$_REGISTRIES_DIR/etag-cache.sh"; then
    _VS_ETAG_LOADED=1
  else
    echo "version-sentinel: failed to source etag-cache.sh" >&2
    return 1
  fi
fi

VS_ETAG_CACHE_BASE="${VS_ETAG_CACHE_BASE:-$PWD}"

VS_REGISTRY_RETRIES=${VS_REGISTRY_RETRIES:-2}
VS_REGISTRY_RETRY_DELAY=${VS_REGISTRY_RETRY_DELAY:-1}

_registry_fetch_json() {
  local url="$1"
  shift
  vs_retry "$VS_REGISTRY_RETRIES" "$VS_REGISTRY_RETRY_DELAY" \
    curl_with_etag "$VS_ETAG_CACHE_BASE" "$url" "$@"
}

# Canonical upstream endpoints are derived from ecosystem/package, never from
# the caller's claimed source. No custom URL can become verification evidence.
registry_url() {
  local eco="$1" pkg="$2" encoded
  encoded=$(printf '%s' "$pkg" | vs_jq -sRr @uri) || return 1
  case "$eco" in
    npm) printf 'https://registry.npmjs.org/%s\n' "$encoded" ;;
    pip|pyproject) printf 'https://pypi.org/pypi/%s/json\n' "$encoded" ;;
    cargo) printf 'https://crates.io/api/v1/crates/%s\n' "$encoded" ;;
    csproj) printf 'https://api.nuget.org/v3-flatcontainer/%s/index.json\n' "$(printf '%s' "$encoded" | tr '[:upper:]' '[:lower:]')" ;;
    *) return 1 ;;
  esac
}

registry_source_valid() {
  local eco="$1" pkg="$2" supplied="$3" canonical
  canonical=$(registry_url "$eco" "$pkg") || return 1
  [[ "$supplied" == "$canonical" ]] && return 0
  case "$eco:$supplied" in
    "npm:https://www.npmjs.com/package/$pkg"|"npm:https://www.npmjs.com/package/$pkg/"|"npm:https://npmjs.com/package/$pkg"|"npm:https://npmjs.com/package/$pkg/") return 0 ;;
    "pip:https://pypi.org/project/$pkg"|"pip:https://pypi.org/project/$pkg/"|"pyproject:https://pypi.org/project/$pkg"|"pyproject:https://pypi.org/project/$pkg/") return 0 ;;
    "cargo:https://crates.io/crates/$pkg"|"cargo:https://crates.io/crates/$pkg/") return 0 ;;
    "csproj:https://www.nuget.org/packages/$pkg"|"csproj:https://www.nuget.org/packages/$pkg/") return 0 ;;
  esac
  return 1
}

# Prints trustworthy online evidence only when the exact, non-yanked release
# exists. Bypass disk cache entirely: a successful HTTP response is mandatory.
registry_verify_version() {
  local eco="$1" pkg="$2" ver="$3" url json latest
  url=$(registry_url "$eco" "$pkg") || return 1
  json=$(VS_REQUIRE_ONLINE=1 VS_ETAG_DISABLE=1 _registry_fetch_json "$url" \
    -A 'version-sentinel (+https://github.com/KSEGIT/Version-Sentinel)') || return 1
  case "$eco" in
    npm)
      latest=$(printf '%s' "$json" | vs_jq -er '.["dist-tags"].latest | select(type=="string" and length>0)') || return 1
      printf '%s' "$json" | vs_jq -e --arg ver "$ver" '(.versions|type)=="object" and (.versions[$ver]|type)=="object"' >/dev/null || return 1 ;;
    pip|pyproject)
      latest=$(printf '%s' "$json" | vs_jq -er '.info.version | select(type=="string" and length>0)') || return 1
      printf '%s' "$json" | vs_jq -e --arg ver "$ver" '.releases[$ver] | type=="array" and length>0 and all(.[]; type=="object") and any(.[]; .yanked==false)' >/dev/null || return 1 ;;
    csproj)
      latest=$(printf '%s' "$json" | vs_jq -er '.versions | select(type=="array" and all(.[]; type=="string" and length>0)) | map(select(contains("-")|not))[-1] | select(type=="string" and length>0)') || return 1
      printf '%s' "$json" | vs_jq -e --arg ver "$ver" '.versions | index($ver) != null' >/dev/null || return 1 ;;
    cargo)
      latest=$(printf '%s' "$json" | vs_jq -er '.crate.max_stable_version | select(type=="string" and length>0)') || return 1
      printf '%s' "$json" | vs_jq -e --arg ver "$ver" 'any(.versions[]; .num==$ver and .yanked!=true)' >/dev/null || return 1 ;;
    *) return 1 ;;
  esac
  vs_jq -nc --arg url "$url" --arg latest "$latest" --arg version "$ver" \
    --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '{url:$url,latest:$latest,version:$version,exists:true,online:true,verifiedAt:$at}'
}

registry_latest() {
  local eco="$1" pkg="$2"
  local url="" json=""
  case "$eco" in
    npm)
      url="https://registry.npmjs.org/$(printf '%s' "$pkg" | vs_jq -sRr @uri)"
      json=$(_registry_fetch_json "$url") || return 1
      echo "$json" | vs_jq -er '.["dist-tags"].latest | select(type=="string" and length>0)' || return 1
      ;;
    pip|pyproject)
      url="https://pypi.org/pypi/$(printf '%s' "$pkg" | vs_jq -sRr @uri)/json"
      json=$(_registry_fetch_json "$url") || return 1
      echo "$json" | vs_jq -er '.info.version | select(type=="string" and length>0)' || return 1
      ;;
    csproj)
      local low
      low=$(printf '%s' "$pkg" | tr '[:upper:]' '[:lower:]')
      url="https://api.nuget.org/v3-flatcontainer/${low}/index.json"
      json=$(_registry_fetch_json "$url") || return 1
      echo "$json" | vs_jq -er '.versions | select(type=="array" and all(.[]; type=="string" and length>0)) | map(select(contains("-")|not))[-1] | select(type=="string" and length>0)' || return 1
      ;;
    cargo)
      url="https://crates.io/api/v1/crates/$(printf '%s' "$pkg" | vs_jq -sRr @uri)"
      json=$(_registry_fetch_json "$url" -A "version-sentinel (+https://github.com/KSEGIT/Version-Sentinel)") || return 1
      echo "$json" | vs_jq -er '.crate.max_stable_version | select(type=="string" and length>0)' || return 1
      ;;
    *) return 1 ;;
  esac
}
