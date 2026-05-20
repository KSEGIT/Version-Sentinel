#!/usr/bin/env bash
# mkdir-based lockfile for portable concurrent-write protection.
# Uses mkdir atomicity — works on Linux, macOS, and Windows (Git Bash / MSYS2).

VS_LOCK_TIMEOUT="${VS_LOCK_TIMEOUT:-5}"
VS_LOCK_STALE_SEC="${VS_LOCK_STALE_SEC:-30}"

vs_lock_acquire() {
  local lockdir="$1"
  local deadline elapsed=0

  while true; do
    if mkdir "$lockdir" 2>/dev/null; then
      echo "$$" > "$lockdir/held"
      return 0
    fi

    # Lock exists — check if stale
    local is_stale=0
    if [[ -f "$lockdir/held" ]]; then
      # Read PID and check liveness
      local holder_pid
      holder_pid=$(cat "$lockdir/held" 2>/dev/null || echo "")

      # Check mtime for staleness
      local mtime now age
      mtime=$(python3 -c "import os,sys; print(int(os.path.getmtime(sys.argv[1])))" "$lockdir/held" 2>/dev/null) || mtime=0
      now=$(python3 -c "import time; print(int(time.time()))")
      age=$((now - mtime))

      if [[ "$age" -ge "$VS_LOCK_STALE_SEC" ]]; then
        # Check if holder process is still alive
        if [[ -n "$holder_pid" ]]; then
          if [[ -d "/proc/$holder_pid" ]] || kill -0 "$holder_pid" 2>/dev/null; then
            # Process is alive — not stale (heartbeat may have failed to update)
            is_stale=0
          else
            # Process is dead — stale
            is_stale=1
          fi
        else
          # No PID found — stale
          is_stale=1
        fi
      fi
    else
      # No held file but lockdir exists — use lockdir mtime as fallback
      local mtime now age
      mtime=$(python3 -c "import os,sys; print(int(os.path.getmtime(sys.argv[1])))" "$lockdir" 2>/dev/null) || mtime=0
      now=$(python3 -c "import time; print(int(time.time()))")
      age=$((now - mtime))
      if [[ "$age" -ge "$VS_LOCK_STALE_SEC" ]]; then
        is_stale=1
      fi
    fi

    if [[ "$is_stale" -eq 1 ]]; then
      rm -rf "$lockdir"
      # Retry mkdir immediately after breaking stale lock
      continue
    fi

    # Check timeout
    if (( $(echo "$elapsed >= $VS_LOCK_TIMEOUT" | bc -l 2>/dev/null || python3 -c "print(1 if $elapsed >= $VS_LOCK_TIMEOUT else 0)") )); then
      echo "version-sentinel: lock acquire timeout after ${VS_LOCK_TIMEOUT}s on $lockdir" >&2
      return 1
    fi

    sleep 0.1
    elapsed=$(python3 -c "print($elapsed + 0.1)")
  done
}

vs_lock_release() {
  local lockdir="$1"
  rm -rf "$lockdir"
}
