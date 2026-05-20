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

path=$(sidecar_path "$PWD")

if coalesce_acquire "$coal_dir" "$ecosystem" "$pkg" "$version"; then
  # We acquired the lock — we're the primary checker
  if sidecar_find_fresh "$path" "$ecosystem" "$pkg" "$version" "$window_hours"; then
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
    if sidecar_find_fresh "$path" "$ecosystem" "$pkg" "$version" "$window_hours"; then
      exit 0
    fi
    (( $(date +%s) >= local_deadline )) && break
    sleep 0.5
  done
fi

cat >&2 <<EOF
BLOCKED: version-sentinel.
Package: $pkg ($ecosystem). Version: $version.
No fresh version check on record (window: ${window_hours}h).

REQUIRED before retry:
1. Run WebSearch (or WebFetch / context7) for the latest version of "$pkg" on the $ecosystem registry.
2. Invoke /vs-record $pkg <latest-version-from-result> <source-url>
3. Retry your edit/install.

Escape: if this pin is intentional (CVE lock, compat constraint, private registry, no-WebSearch region),
run: /vs-record $pkg $version "intentional: <reason>"
EOF
exit 2
