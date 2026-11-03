#!/usr/bin/env bash
# A successful audit is evidence for the exact project inventory and contents.
set -u
DIR="$(cd "$(dirname "$0")" && pwd)"
source "$DIR/lib/options.sh"
if [[ "${VS_DISABLE:-0}" == 1 ]]; then exit 0; fi
bash "$DIR/audit-state.sh" invalidate "$PWD" || exit 2
for prerequisite in jq curl python3; do
  if ! command -v "$prerequisite" >/dev/null 2>&1; then
    echo "BLOCKED: version-sentinel. $prerequisite missing; cannot complete mandatory audit." >&2
    exit 2
  fi
done
source "$DIR/lib/registries.sh"
source "$DIR/lib/sidecar.sh"
source "$DIR/lib/circuit-breaker.sh"
# begin revokes prior evidence before any registry requests.
snapshot=$(bash "$DIR/audit-state.sh" begin "$PWD") || exit 2
VS_CB_STATE=$(mktemp -d) || exit 2
trap 'rm -rf "$VS_CB_STATE"' EXIT
export VS_REQUIRE_ONLINE=1
printf '%-12s %-40s %-15s %-15s %s\n' ECOSYSTEM PACKAGE CURRENT LATEST STATUS
printf '%s\n' '-----------------------------------------------------------------------------------------'
sidecar_file=$(sidecar_path "$PWD")
failed=0
while IFS= read -r name; do
  [[ -z "$name" ]] && continue
  mf="$PWD/$name"
  case "$name" in
    */package.json|package.json) eco=npm ;;
    */requirements*.txt|requirements*.txt|*/constraints*.txt|constraints*.txt) eco=pip ;;
    */pyproject.toml|pyproject.toml) eco=pyproject ;;
    */Cargo.toml|Cargo.toml) eco=cargo ;;
    *.csproj|*.fsproj|*.vbproj) eco=csproj ;;
    *) echo "BLOCKED: version-sentinel. Unsupported required manifest $name" >&2; failed=1; continue ;;
  esac
  parsed=$(bash "$DIR/audit-state.sh" deps "$mf") || { failed=1; continue; }
  while IFS=$'\t' read -r pkg cur; do
    [[ -z "$pkg" ]] && continue
    if cb_is_open "$VS_CB_STATE" "$eco"; then
      latest='?'; status=circuit-open; failed=1
    elif latest=$(registry_latest "$eco" "$pkg") && [[ -n "$latest" ]]; then
      cb_record_success "$VS_CB_STATE" "$eco"
      status=ok
      if [[ "$cur" == __version_sentinel_unpinned__ ]]; then
        cur='(unpinned)'; status=UNPINNED
      elif [[ "$cur" != "$latest" ]]; then
        intentional=$(sidecar_read "$sidecar_file" | jq -r --arg e "$eco" --arg p "$pkg" --arg v "$cur" '.entries[] | select(.ecosystem==$e and .pkg==$p and .version==$v and (.source|startswith("intentional:"))) | .source' | head -1)
        if [[ -n "$intentional" ]]; then status=intentional-pin; else status=DRIFT; fi
      fi
    else
      cb_record_failure "$VS_CB_STATE" "$eco"
      latest='?'; status=lookup-failed; failed=1
    fi
    printf '%-12s %-40s %-15s %-15s %s\n' "$eco" "$pkg" "$cur" "$latest" "$status"
  done <<< "$parsed"
done <<< "$(printf '%s' "$snapshot" | jq -r '.required[]' | tr -d '\r')"
if [[ "$failed" != 0 ]]; then
  echo 'BLOCKED: version-sentinel. Mandatory audit failed due to registry lookup/manifest errors. Resolve the errors and rerun; version drift alone does not fail an audit.' >&2
  exit 2
fi
bash "$DIR/audit-state.sh" complete "$PWD" "$snapshot" || exit 2
echo 'version-sentinel: mandatory online dependency audit completed; no dependency versions changed.'
