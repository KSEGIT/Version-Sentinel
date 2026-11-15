#!/usr/bin/env bash
# Normalize native Windows jq output without hiding a parse failure.
# jq emits escaped CR inside JSON; raw CRLF line endings are transport only.
vs_jq() {
  local output status
  output=$(command jq "$@")
  status=$?
  [[ "$status" -eq 0 ]] || return "$status"
  printf '%s\n' "${output//$'\r'/}"
}
