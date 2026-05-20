#!/usr/bin/env bash
# File-based circuit breaker, per-registry.
# State stored in temp dir as simple counter files.
# Uses append-and-count for atomic increments (avoids read-modify-write race).

VS_CB_THRESHOLD=${VS_CB_THRESHOLD:-3}

cb_reset() {
  local state_dir="$1"
  rm -f "$state_dir"/.vs_cb_*
}

cb_record_failure() {
  local state_dir="$1" registry="$2"
  local counter_file="$state_dir/.vs_cb_${registry}"
  printf '.\n' >> "$counter_file"
}

cb_record_success() {
  local state_dir="$1" registry="$2"
  rm -f "$state_dir/.vs_cb_${registry}"
}

cb_is_open() {
  local state_dir="$1" registry="$2"
  local counter_file="$state_dir/.vs_cb_${registry}"
  [[ ! -f "$counter_file" ]] && return 1
  local count
  count=$(wc -l < "$counter_file" 2>/dev/null | tr -d ' ') || count=0
  [[ "$count" -ge "$VS_CB_THRESHOLD" ]]
}
