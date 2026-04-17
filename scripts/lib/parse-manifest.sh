#!/usr/bin/env bash
# parse-manifest.sh — per-ecosystem manifest parsers.
# Each parser prints TAB-separated "pkg\tversion" lines, one per dependency.
# Version prefixes (^ ~ >= <= = v) are stripped.
# Local/git/workspace refs are skipped.
# Missing/invalid file → empty output, exit 0 (fail-open).

_strip_version_prefix() {
  sed -E 's/^[v^~><= ]+//' <<< "$1"
}

_is_registry_version() {
  local raw="$1"
  case "$raw" in
    file:*|git+*|git:*|github:*|workspace:*|link:*|portal:*|npm:*|"*"|""|latest|next) return 1 ;;
  esac
  return 0
}

parse_npm() {
  local file="$1"
  [[ -f "$file" ]] || return 0
  jq -r '[.dependencies, .devDependencies, .peerDependencies, .optionalDependencies]
         | map(select(. != null)) | add // {} | to_entries[] | "\(.key)\t\(.value)"' \
    "$file" 2>/dev/null | while IFS=$'\t' read -r pkg raw; do
      [[ -z "$pkg" ]] && continue
      _is_registry_version "$raw" || continue
      local ver
      ver=$(_strip_version_prefix "$raw")
      [[ "$ver" =~ [[:space:]] ]] && continue
      printf '%s\t%s\n' "$pkg" "$ver"
    done
}
