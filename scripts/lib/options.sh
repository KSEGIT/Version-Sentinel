#!/usr/bin/env bash
# Map plugin userConfig env vars (CLAUDE_PLUGIN_OPTION_*) onto legacy VS_* vars.
# Source from any hook script before reading VS_DISABLE / VS_WINDOW_HOURS.
# User-set VS_* wins so the shell escape hatch still works.

if [[ -z "${VS_DISABLE:-}" ]]; then
  case "${CLAUDE_PLUGIN_OPTION_DISABLE:-false}" in
    1|true|TRUE|True) VS_DISABLE=1 ;;
    *) VS_DISABLE=0 ;;
  esac
  export VS_DISABLE
fi

if [[ -z "${VS_WINDOW_HOURS:-}" ]]; then
  if [[ -n "${CLAUDE_PLUGIN_OPTION_WINDOW_HOURS:-}" ]]; then
    VS_WINDOW_HOURS="${CLAUDE_PLUGIN_OPTION_WINDOW_HOURS}"
    export VS_WINDOW_HOURS
  fi
fi
