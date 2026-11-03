#!/usr/bin/env bash
# Usage: check-sidecar.sh <ecosystem> <pkg> <version>
# Exit 0 = allow (fresh entry found or VS_DISABLE set)
# Exit 2 = block (no fresh entry); stderr carries message for Claude
set -u

ecosystem="${1:?ecosystem required}"
pkg="${2:?pkg required}"
version="${3:?version required}"

# shellcheck source=lib/options.sh
source "$(dirname "$0")/lib/options.sh"

window_hours="${VS_WINDOW_HOURS:-24}"

if [[ "${VS_DISABLE:-0}" == "1" ]]; then
  exit 0
fi

# shellcheck source=lib/coalesce.sh
source "$(dirname "$0")/lib/coalesce.sh"

coal_dir="${TMPDIR:-/tmp}"

# shellcheck source=lib/sidecar.sh
source "$(dirname "$0")/lib/sidecar.sh"
source "$(dirname "$0")/lib/registries.sh"

for prerequisite in jq python3; do
  if ! command -v "$prerequisite" >/dev/null 2>&1; then
    echo "BLOCKED: version-sentinel. $prerequisite missing; cannot validate online evidence." >&2
    exit 2
  fi
done
project_root=$(cd "${VS_PROJECT_ROOT:-$PWD}" && pwd -P) || exit 2
path=$(sidecar_path "$project_root")
registry_endpoint=$(registry_url "$ecosystem" "$pkg") || exit 2

if coalesce_acquire "$coal_dir" "$ecosystem" "$pkg" "$version"; then
  # We acquired the lock — we're the primary checker
  if sidecar_find_verified "$path" "$ecosystem" "$pkg" "$version" "$window_hours" "$project_root" "$registry_endpoint"; then
    coalesce_release "$coal_dir" "$ecosystem" "$pkg" "$version"
    exit 0
  fi
  coalesce_release "$coal_dir" "$ecosystem" "$pkg" "$version"
else
  # Another process is checking this package (in-flight).
  # Wait for a fresh sidecar entry to appear, then allow; time out and block.
  local_timeout="${VS_COALESCE_TTL:-10}"
  local_deadline=$(( $(date +%s) + local_timeout ))
  while true; do
    if sidecar_find_verified "$path" "$ecosystem" "$pkg" "$version" "$window_hours" "$project_root" "$registry_endpoint"; then
      exit 0
    fi
    (( $(date +%s) >= local_deadline )) && break
    sleep 0.5
  done
fi

cat >&2 <<EOF
BLOCKED: version-sentinel.
Package: $pkg ($ecosystem). Version: $version.
No fresh successful online version check on record for this project (window: ${window_hours}h).

REQUIRED before retry:
1. Inspect the latest release on the $ecosystem registry.
2. Invoke /vs-record $ecosystem $pkg $version <canonical-https-source-url>; this performs online verification.
3. Retry your edit/install.

For an intentional older pin (CVE lock or compatibility), run:
/vs-record $ecosystem $pkg $version "intentional: <reason>"
Older pins still require a successful online check. URL-only and post-install records cannot authorize changes.
EOF
exit 2
