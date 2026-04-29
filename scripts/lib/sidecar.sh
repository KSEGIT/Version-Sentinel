#!/usr/bin/env bash
# Sidecar JSON state for version-sentinel.
# Keyed by (ecosystem, pkg); last-write-wins dedupe.

SCRIPT_DIR_SIDECAR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -z "${_VS_LOCKFILE_LOADED:-}" ]]; then
  source "$SCRIPT_DIR_SIDECAR/lockfile.sh"
  _VS_LOCKFILE_LOADED=1
fi

sidecar_path() {
  local cwd="${1:-$PWD}"
  if [[ -w "$cwd" ]]; then
    echo "$cwd/.version-sentinel/checks.json"
    return 0
  fi
  local data="${CLAUDE_PLUGIN_DATA:-$HOME/.claude/plugins/data/version-sentinel}"
  echo "$data/checks.json"
}

sidecar_read() {
  local path="$1"
  if [[ ! -f "$path" ]]; then
    echo '{"entries":[]}'
    return 0
  fi
  if ! jq -e '.entries' "$path" >/dev/null 2>&1; then
    echo "version-sentinel: sidecar corrupt, treating as empty: $path" >&2
    echo '{"entries":[]}'
    return 0
  fi
  cat "$path"
}

sidecar_find_fresh() {
  local path="$1" ecosystem="$2" pkg="$3" version="$4" window="$5"
  local now="${VS_NOW_OVERRIDE:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}"
  local now_epoch
  now_epoch=$(_iso_to_epoch "$now") || return 1
  local entry
  entry=$(sidecar_read "$path" | jq -c \
    --arg eco "$ecosystem" --arg pkg "$pkg" --arg ver "$version" \
    '.entries[] | select(.ecosystem==$eco and .pkg==$pkg and .version==$ver)')
  [[ -z "$entry" ]] && return 1
  local checked
  checked=$(echo "$entry" | jq -r '.checkedAt')
  local checked_epoch
  checked_epoch=$(_iso_to_epoch "$checked") || return 1
  local delta=$((now_epoch - checked_epoch))
  local window_sec=$((window * 3600))
  [[ "$delta" -ge 0 && "$delta" -le "$window_sec" ]]
}

sidecar_write_entry() {
  local path="$1" ecosystem="$2" pkg="$3" version="$4" source="$5"
  local checked="${6:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}"
  local dir
  dir=$(dirname "$path")
  mkdir -p "$dir"
  local gi="$dir/.gitignore"
  if [[ ! -f "$gi" ]]; then
    printf '*\n!.gitignore\n' > "$gi"
  fi
  local lockpath="$dir/.vs-write.lock"
  vs_lock_acquire "$lockpath" || return 1
  local current updated
  current=$(sidecar_read "$path")
  updated=$(echo "$current" | jq -c \
    --arg eco "$ecosystem" --arg pkg "$pkg" --arg ver "$version" \
    --arg src "$source" --arg at "$checked" \
    '.entries = ((.entries // []) | map(select(.ecosystem != $eco or .pkg != $pkg))
      + [{ecosystem: $eco, pkg: $pkg, version: $ver, source: $src, checkedAt: $at}])') \
    || { vs_lock_release "$lockpath"; echo "version-sentinel: jq failed, aborting write" >&2; return 1; }
  [[ -n "$updated" ]] || { vs_lock_release "$lockpath"; echo "version-sentinel: jq produced empty output, aborting write" >&2; return 1; }
  printf '%s\n' "$updated" > "$path"
  sidecar_prune "$path" "${VS_PRUNE_DAYS:-30}"
  vs_lock_release "$lockpath"
}

sidecar_prune() {
  local path="$1" max_age_days="$2"
  [[ ! -f "$path" ]] && return 0
  local now="${VS_NOW_OVERRIDE:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}"
  local now_epoch
  now_epoch=$(_iso_to_epoch "$now") || return 1
  local cutoff=$((now_epoch - max_age_days * 86400))
  local updated
  updated=$(jq -c --arg cutoff "$cutoff" \
    '.entries = [.entries[] | select((.checkedAt | strptime("%Y-%m-%dT%H:%M:%SZ") | mktime) >= ($cutoff | tonumber))]' \
    "$path") || return 1
  printf '%s\n' "$updated" > "$path"
}

_iso_to_epoch() {
  python3 -c 'import sys, datetime; print(int(datetime.datetime.strptime(sys.argv[1], "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=datetime.timezone.utc).timestamp()))' "$1" 2>/dev/null
}
