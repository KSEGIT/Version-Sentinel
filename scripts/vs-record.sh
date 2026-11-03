#!/usr/bin/env bash
# Usage: vs-record.sh <ecosystem> <pkg> <version> <source>
set -u

if [[ $# -lt 4 ]]; then
  cat >&2 <<EOF
Usage: /vs-record <ecosystem> <pkg> <version> <source>

<source> must be one of:
  - canonical https:// URL to this package's upstream registry page
  - intentional:<reason>

Ecosystems (v0.1): npm, pip, cargo, csproj, pyproject
EOF
  exit 1
fi

ecosystem="$1"
pkg="$2"
version="$3"
source="$4"

# Whitelist ecosystem
case "$ecosystem" in
  npm|pip|cargo|csproj|pyproject) ;;
  *)
    echo "version-sentinel: unknown ecosystem '$ecosystem'. Supported: npm, pip, cargo, csproj, pyproject" >&2
    exit 1
    ;;
esac

# Validate version shape: reject empty, whitespace-only, or containing spaces.
if [[ ! "$version" =~ ^[0-9][0-9A-Za-z.+-]*$ ]]; then
  echo "version-sentinel: empty/invalid version '$version'" >&2
  exit 1
fi

# Validate package name: reject '/' except for npm scoped names (@scope/name).
if [[ ! "$pkg" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]; then
  if [[ "$ecosystem" == "npm" && "$pkg" =~ ^@[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$ ]]; then
    : # allow npm scoped name
  else
    echo "version-sentinel: invalid package name '$pkg'" >&2
    exit 1
  fi
fi

case "$source" in
  https://*) ;;
  intentional:*)
    reason="${source#intentional:}"
    if [[ ! "$reason" =~ [^[:space:]] ]]; then
      echo 'version-sentinel: intentional: requires a nonempty reason' >&2
      exit 1
    fi ;;
  *)
    echo "version-sentinel: invalid source '$source'." >&2
    echo "Expected canonical https:// registry URL or intentional:<reason>." >&2
    exit 1
    ;;
esac

DIR="$(dirname "$0")"
source "$DIR/lib/sidecar.sh"
source "$DIR/lib/registries.sh"

for prerequisite in curl jq python3; do
  if ! command -v "$prerequisite" >/dev/null 2>&1; then
    echo "version-sentinel: $prerequisite missing; cannot verify online" >&2
    exit 1
  fi
done
if [[ "$source" != intentional:* ]] && ! registry_source_valid "$ecosystem" "$pkg" "$source"; then
  echo 'version-sentinel: source must be the canonical https registry URL or package page for this package' >&2
  exit 1
fi
if ! evidence=$(registry_verify_version "$ecosystem" "$pkg" "$version"); then
  echo "version-sentinel: online verification failed for $ecosystem/$pkg@$version (network, invalid response, missing or yanked version); no check recorded" >&2
  exit 1
fi
latest=$(printf '%s' "$evidence" | jq -r '.latest')
if [[ "$latest" != "$version" && "$source" != intentional:* ]]; then
  echo "version-sentinel: latest is $latest; version $version needs intentional:<reason> and successful online verification" >&2
  exit 1
fi
project_root=$(cd "${VS_PROJECT_ROOT:-$PWD}" && pwd -P) || exit 1
verified_at=$(printf '%s' "$evidence" | jq -r '.verifiedAt')

path=$(sidecar_path "$project_root")
sidecar_write_entry "$path" "$ecosystem" "$pkg" "$version" "$source" "$verified_at" "$evidence" "$project_root" || exit 1
echo "recorded: $ecosystem/$pkg@$version (source: $source)"
