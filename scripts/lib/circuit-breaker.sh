#!/usr/bin/env bash
# File-based circuit breaker, per-registry.
# State stored in temp dir as simple counter files.

VS_CB_THRESHOLD=${VS_CB_THRESHOLD:-3}

cb_reset() {
  local state_dir="$1"
  rm -f "$state_dir"/.vs_cb_*
}

cb_record_failure() {
  local state_dir="$1" registry="$2"
  local counter_file="$state_dir/.vs_cb_${registry}"
  local count=0
  [[ -f "$counter_file" ]] && count=$(cat "$counter_file")
  echo $((count + 1)) > "$counter_file"
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
  count=$(cat "$counter_file")
  [[ "$count" -ge "$VS_CB_THRESHOLD" ]]
}
