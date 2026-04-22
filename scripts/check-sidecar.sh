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

# shellcheck source=lib/sidecar.sh
source "$(dirname "$0")/lib/sidecar.sh"

path=$(sidecar_path "$PWD")

if sidecar_find_fresh "$path" "$ecosystem" "$pkg" "$version" "$window_hours"; then
  exit 0
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
