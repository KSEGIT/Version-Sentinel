#!/usr/bin/env bash
# Request coalescing: prevent duplicate sidecar checks for the same package
# when multiple hooks fire in parallel. Uses temp marker files with a 10s TTL.

VS_COALESCE_TTL=${VS_COALESCE_TTL:-10}

_coalesce_marker() {
  local dir="$1" eco="$2" pkg="$3" ver="$4"
  local safe_pkg="${pkg//\//_}"
  echo "$dir/.vs_coal_${eco}_${safe_pkg}_${ver}"
}

coalesce_acquire() {
  local dir="$1" eco="$2" pkg="$3" ver="$4"
  local marker
  marker=$(_coalesce_marker "$dir" "$eco" "$pkg" "$ver")
  if [[ -f "$marker" ]]; then
    local age
    local py_marker="$marker"
    if command -v cygpath >/dev/null 2>&1; then
      py_marker=$(cygpath -w "$marker")
    fi
    age=$(python3 -c "import os,time;print(int(time.time()-os.path.getmtime(r'$py_marker')))" 2>/dev/null || echo 0)
    if [[ "$age" -lt "$VS_COALESCE_TTL" ]]; then
      return 1
    fi
    rm -f "$marker"
  fi
  echo "$$" > "$marker"
  return 0
}

coalesce_release() {
  local dir="$1" eco="$2" pkg="$3" ver="$4"
  local marker
  marker=$(_coalesce_marker "$dir" "$eco" "$pkg" "$ver")
  rm -f "$marker"
}
