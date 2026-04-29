#!/usr/bin/env bash
set -u

DIR="$(dirname "$0")"
source "$DIR/lib/parse-manifest.sh"
source "$DIR/lib/registries.sh"
source "$DIR/lib/sidecar.sh"
source "$DIR/lib/circuit-breaker.sh"

VS_CB_STATE="$(mktemp -d)"
trap 'rm -rf "$VS_CB_STATE"' EXIT

if ! command -v curl >/dev/null 2>&1; then
  echo "version-sentinel: curl missing, cannot audit" >&2; exit 1
fi

manifests=$(find . -maxdepth 4 \
  \( -name package.json -o -name 'requirements*.txt' -o -name 'constraints*.txt' \
     -o -name pyproject.toml -o -name Cargo.toml \
     -o -name '*.csproj' -o -name '*.fsproj' -o -name '*.vbproj' \) \
  -not -path '*/node_modules/*' -not -path '*/.git/*' -not -path '*/target/*' \
  -not -path '*/.venv/*' -not -path '*/venv/*' 2>/dev/null)

printf '%-12s %-40s %-15s %-15s %s\n' ECOSYSTEM PACKAGE "CURRENT" "LATEST" STATUS
printf '%s\n' "-----------------------------------------------------------------------------------------"

sidecar=$(sidecar_path "$PWD")

while IFS= read -r mf; do
  [[ -z "$mf" ]] && continue
  eco=$(ecosystem_for_path "$mf")
  [[ -z "$eco" ]] && continue
  while IFS=$'\t' read -r pkg cur; do
    [[ -z "$pkg" ]] && continue
    if cb_is_open "$VS_CB_STATE" "$eco"; then
      latest="?"
      status="circuit-open"
    else
      latest=$(registry_latest "$eco" "$pkg" 2>/dev/null || echo "?")
      if [[ -z "$latest" || "$latest" == "?" ]]; then
        cb_record_failure "$VS_CB_STATE" "$eco"
        status="lookup-failed"
      else
        cb_record_success "$VS_CB_STATE" "$eco"
        status="ok"
      fi
    fi
    if [[ "$status" == "ok" && "$cur" != "$latest" ]]; then
      intentional=$(sidecar_read "$sidecar" | jq -r --arg e "$eco" --arg p "$pkg" \
        '.entries[] | select(.ecosystem==$e and .pkg==$p and (.source|startswith("intentional:"))) | .source' | head -1)
      if [[ -n "$intentional" ]]; then
        status="intentional-pin"
      else
        status="DRIFT"
      fi
    fi
    printf '%-12s %-40s %-15s %-15s %s\n' "$eco" "$pkg" "$cur" "${latest:-?}" "$status"
    sleep 0.2
  done <<< "$(parse_manifest_by_path "$mf")"
done <<< "$manifests"
