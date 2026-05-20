#!/usr/bin/env bash
# vs_retry <max_attempts> <base_delay_sec> <cmd...>
# Retries cmd up to max_attempts times with exponential backoff.
# Returns last exit code on exhaustion. Stdout of successful attempt is printed.
# stderr from the last failed attempt is forwarded to stderr on exhaustion.
# Note: the temp file is cleaned up on normal return; SIGKILL leaks are left to OS /tmp cleanup.

vs_retry() {
  local max="$1" delay="$2"
  shift 2

  # Validate max is a positive integer
  if ! [[ "$max" =~ ^[0-9]+$ ]] || [[ "$max" -le 0 ]]; then
    echo "version-sentinel: vs_retry requires max_attempts to be a positive integer, got: $max" >&2
    return 1
  fi

  local attempt=1 rc=0 output="" last_err=""
  local err_file
  err_file=$(mktemp) || { echo "version-sentinel: failed to create temp file" >&2; return 1; }
  while [[ "$attempt" -le "$max" ]]; do
    output=$("$@" 2>"$err_file") && { echo "$output"; rm -f "$err_file"; return 0; }
    rc=$?
    last_err=$(cat "$err_file" 2>/dev/null)
    attempt=$((attempt + 1))
    if [[ "$attempt" -le "$max" ]]; then
      sleep "$delay"
      delay=$(python3 -c "print($delay * 2)" 2>/dev/null || echo "$delay")
      delay="${delay%$'\r'}"
    fi
  done
  rm -f "$err_file"
  [[ -n "$last_err" ]] && echo "version-sentinel: retry exhausted: $last_err" >&2
  return "$rc"
}
