#!/usr/bin/env bash
# registry_latest <ecosystem> <pkg> → prints latest version string, exit 0
# Exits 1 on failure.

registry_latest() {
  local eco="$1" pkg="$2"
  local url="" json=""
  case "$eco" in
    npm)
      url="https://registry.npmjs.org/$(printf '%s' "$pkg" | jq -sRr @uri)"
      json=$(curl -fsSL "$url") || return 1
      echo "$json" | jq -r '.["dist-tags"].latest // empty'
      ;;
    pip|pyproject)
      url="https://pypi.org/pypi/$(printf '%s' "$pkg" | jq -sRr @uri)/json"
      json=$(curl -fsSL "$url") || return 1
      echo "$json" | jq -r '.info.version // empty'
      ;;
    csproj)
      local low
      low=$(printf '%s' "$pkg" | tr '[:upper:]' '[:lower:]')
      url="https://api.nuget.org/v3-flatcontainer/${low}/index.json"
      json=$(curl -fsSL "$url") || return 1
      echo "$json" | jq -r '.versions[-1] // empty'
      ;;
    cargo)
      url="https://crates.io/api/v1/crates/$(printf '%s' "$pkg" | jq -sRr @uri)"
      json=$(curl -fsSL -A "version-sentinel (+https://github.com/KSEGIT/Version-Sentinel)" "$url") || return 1
      echo "$json" | jq -r '.crate.max_stable_version // empty'
      ;;
    *) return 1 ;;
  esac
}
