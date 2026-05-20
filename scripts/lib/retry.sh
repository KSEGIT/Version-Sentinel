#!/usr/bin/env bash
# vs_retry <max_attempts> <base_delay_sec> <cmd...>
# Retries cmd up to max_attempts times with exponential backoff.
# Returns last exit code on exhaustion. Stdout of successful attempt is printed.
# stderr from the last failed attempt is forwarded to stderr on exhaustion.

vs_retry() {
  local max="$1" delay="$2"
  shift 2
  local attempt=1 rc=0 output="" last_err=""
  local err_file="/tmp/_vs_retry_err_$$"
  while [[ "$attempt" -le "$max" ]]; do
    output=$("$@" 2>"$err_file") && { echo "$output"; rm -f "$err_file"; return 0; }
    rc=$?
    last_err=$(cat "$err_file" 2>/dev/null)
    attempt=$((attempt + 1))
    if [[ "$attempt" -le "$max" ]]; then
      sleep "$delay"
      delay=$(python3 -c "print($delay * 2)" 2>/dev/null || echo "$delay")
    fi
  done
  rm -f "$err_file"
  [[ -n "$last_err" ]] && echo "version-sentinel: retry exhausted: $last_err" >&2
  return "$rc"
}
