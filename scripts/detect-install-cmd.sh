#!/usr/bin/env bash
set -u

DIR="$(dirname "$0")"
# shellcheck source=lib/options.sh
source "$DIR/lib/options.sh"
# shellcheck source=lib/platform.sh
source "$DIR/lib/platform.sh"

if [[ "${VS_DISABLE:-0}" == "1" ]]; then exit 0; fi

# shellcheck source=lib/parse-install-cmd.sh
source "$DIR/lib/parse-install-cmd.sh"

input=$(cat)

if ! command -v jq >/dev/null 2>&1; then
  echo "version-sentinel: jq missing, fail-open" >&2; exit 0
fi
if ! echo "$input" | jq -e . >/dev/null 2>&1; then exit 0; fi

tool_name=$(echo "$input" | jq -r '.tool_name // empty')
tool_name=$(normalize_tool_name "$tool_name")
[[ "$tool_name" != "Bash" ]] && exit 0

cmd=$(echo "$input" | jq -r '.tool_input.command // empty')
[[ -z "$cmd" ]] && exit 0

matches=$(parse_install_cmd "$cmd")
[[ -z "$matches" ]] && exit 0

unpinned_install_message() {
  local eco="$1" pkg="$2" retry
  case "$eco" in
    npm) retry="npm install $pkg@<version>" ;;
    pip) retry="pip install $pkg==<version>" ;;
    cargo) retry="cargo add $pkg@<version>" ;;
    csproj) retry="dotnet add package $pkg --version <version>" ;;
    *) retry="install $pkg at <version>" ;;
  esac
  cat <<EOF
BLOCKED: version-sentinel.
Package: $pkg ($eco).
No explicit registry version was provided. Floating tags and omitted versions cannot be recorded as an exact version check.

REQUIRED before retry:
1. Look up the current version of "$pkg" on the $eco registry.
2. Record that exact version and the source URL with /vs-record.
3. Retry with an explicit version: $retry
EOF
}

block=0
block_msgs=""
while IFS=$'\t' read -r eco pkg ver; do
  if [[ "$eco" == "$VS_PARSE_AMBIGUOUS_ECOSYSTEM" ]]; then
    block=1
    block_msgs+="BLOCKED: version-sentinel."$'\n'"Cannot safely inspect command: $pkg."$'\n---\n'
    continue
  fi
  [[ -z "$pkg" ]] && continue
  if [[ "$ver" == "$VS_UNPINNED_VERSION" ]]; then
    block=1
    block_msgs+=$(unpinned_install_message "$eco" "$pkg")$'\n---\n'
    continue
  fi
  [[ -z "$ver" ]] && continue
  if ! bash "$DIR/check-sidecar.sh" "$eco" "$pkg" "$ver" 2>/tmp/_vs_err_$$; then
    block=1
    block_msgs+=$(cat /tmp/_vs_err_$$)$'\n---\n'
  fi
done <<< "$matches"
rm -f /tmp/_vs_err_$$

if [[ "$block" -eq 1 ]]; then
  echo "$block_msgs" >&2
  exit 2
fi
exit 0
