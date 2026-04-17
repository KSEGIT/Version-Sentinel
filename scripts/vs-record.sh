#!/usr/bin/env bash
# Usage: vs-record.sh <ecosystem> <pkg> <version> <source>
set -u

if [[ $# -lt 4 ]]; then
  cat >&2 <<EOF
Usage: /vs-record <ecosystem> <pkg> <version> <source>

<source> must be one of:
  - http(s):// URL to registry page
  - intentional:<reason>

Ecosystems (v0.1): npm, pip, cargo, csproj, pyproject
EOF
  exit 1
fi

ecosystem="$1"
pkg="$2"
version="$3"
source="$4"

case "$source" in
  http://*|https://*) ;;
  intentional:*) ;;
  *)
    echo "version-sentinel: invalid source '$source'." >&2
    echo "Expected http(s):// URL or intentional:<reason>." >&2
    exit 1
    ;;
esac

DIR="$(dirname "$0")"
source "$DIR/lib/sidecar.sh"

path=$(sidecar_path "$PWD")
sidecar_write_entry "$path" "$ecosystem" "$pkg" "$version" "$source"
echo "recorded: $ecosystem/$pkg@$version (source: $source)"
