#!/usr/bin/env bash
# mkdir-based lockfile for portable concurrent-write protection.
# Uses mkdir atomicity — works on Linux, macOS, and Windows (Git Bash / MSYS2).

VS_LOCK_TIMEOUT="${VS_LOCK_TIMEOUT:-5}"
VS_LOCK_STALE_SEC="${VS_LOCK_STALE_SEC:-30}"

vs_lock_acquire() {
  local lockdir="$1"
  local deadline=$(( $(date +%s) + VS_LOCK_TIMEOUT ))

  while true; do
    if mkdir "$lockdir" 2>/dev/null; then
      echo "$$" > "$lockdir/held"
      return 0
    fi

    # Lock exists — check if stale
    local is_stale=0
    if [[ -f "$lockdir/held" ]]; then
      # Get PID and mtime-age in a single python3 call
      local holder_pid age
      read -r holder_pid age < <(python3 -c "
import os, sys, time
hf = sys.argv[1]
try:
    pid = open(hf).read().strip()
    age = int(time.time() - os.path.getmtime(hf))
except Exception:
    pid, age = '', 999
print(pid, age)
" "$lockdir/held" 2>/dev/null || echo " 999")

      if [[ "$age" -ge "$VS_LOCK_STALE_SEC" ]]; then
        if [[ -n "$holder_pid" ]]; then
          if [[ -d "/proc/$holder_pid" ]] || kill -0 "$holder_pid" 2>/dev/null; then
            is_stale=0  # process alive — not stale despite age
          else
            is_stale=1  # process dead — stale
          fi
        else
          is_stale=1  # no PID recorded — stale
        fi
      fi
    else
      # No held file: use lockdir mtime as fallback (single python3 call)
      local age
      age=$(python3 -c "
import os, sys, time
try:
    print(int(time.time() - os.path.getmtime(sys.argv[1])))
except Exception:
    print(999)
" "$lockdir" 2>/dev/null || echo 999)
      [[ "$age" -ge "$VS_LOCK_STALE_SEC" ]] && is_stale=1
    fi

    if [[ "$is_stale" -eq 1 ]]; then
      rm -rf "$lockdir"
      continue
    fi

    if (( $(date +%s) >= deadline )); then
      echo "version-sentinel: lock acquire timeout after ${VS_LOCK_TIMEOUT}s on $lockdir" >&2
      return 1
    fi

    sleep 0.1
  done
}

vs_lock_release() {
  local lockdir="$1"
  rm -rf "$lockdir"
}
