#!/usr/bin/env bash
# vs_retry <max_attempts> <base_delay_sec> <cmd...>
# Retries cmd up to max_attempts times with exponential backoff.
# Returns last exit code on exhaustion. Stdout of successful attempt is printed.

vs_retry() {
  local max="$1" delay="$2"
  shift 2
  local attempt=1 rc=0 output=""
  while [[ "$attempt" -le "$max" ]]; do
    output=$("$@" 2>/dev/null) && { echo "$output"; return 0; }
    rc=$?
    attempt=$((attempt + 1))
    if [[ "$attempt" -le "$max" ]]; then
      sleep "$delay"
      delay=$(python3 -c "print($delay * 2)" 2>/dev/null || echo "$delay")
    fi
  done
  return "$rc"
}
