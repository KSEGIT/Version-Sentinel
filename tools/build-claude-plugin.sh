#!/usr/bin/env bash
# Build the Claude directory package without repository-only files.
set -euo pipefail

if [[ "$#" -ne 1 ]]; then
  echo 'Usage: bash tools/build-claude-plugin.sh ABSOLUTE_OUTPUT_DIR' >&2
  exit 1
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
python3 - "$ROOT" "$1" <<'PY'
from pathlib import Path
import shutil
import stat
import sys

root = Path(sys.argv[1])
destination = Path(sys.argv[2])
if not destination.is_absolute():
    sys.exit('Claude package output must be an absolute path')
if destination.exists() or destination.is_symlink():
    sys.exit(f'Claude package output already exists: {destination}')

# Keep this list explicit: new website, test, or build files must not become
# installable code simply because they were added to a source directory.
files = '''
.claude-plugin/plugin.json
hooks/hooks.json
scripts/audit-state.sh
scripts/auto-record.sh
scripts/check-sidecar.sh
scripts/check-versions.sh
scripts/detect-install-cmd.sh
scripts/detect-manifest-edit.sh
scripts/lib/circuit-breaker.sh
scripts/lib/coalesce.sh
scripts/lib/etag-cache.sh
scripts/lib/install-context.py
scripts/lib/json.sh
scripts/lib/lockfile.sh
scripts/lib/manifest-edit.py
scripts/lib/npm_reconcile.py
scripts/lib/options.sh
scripts/lib/parse-install-cmd.sh
scripts/lib/parse-manifest.sh
scripts/lib/path_helpers.py
scripts/lib/platform.sh
scripts/lib/project-state.py
scripts/lib/registries.sh
scripts/lib/retry.sh
scripts/lib/sidecar.sh
scripts/prereq-check.sh
scripts/recover-manifest.sh
scripts/reconcile-npm-lock.sh
scripts/security-check.sh
scripts/lib/security.py
scripts/lib/security-settings.py
scripts/lib/security-post.py
scripts/retire-manifest.sh
scripts/session-start.sh
scripts/vs-record.sh
commands/vs-record.md
commands/check-versions.md
agents/version-reviewer.agent.md
skills/version-sentinel/SKILL.md
skills/audit-dependencies/SKILL.md
LICENSE
PRIVACY.md
docs/enforcement.md
'''.split()
entries = [(Path(name), Path(name)) for name in files]
entries.append((Path('packaging/claude/README.md'), Path('README.md')))

# Validate the complete source set before creating output. Do not follow links
# that could make a package depend on files outside its source checkout.
for source_relative, _ in entries:
    source = root / source_relative
    for part in [source, *source.parents]:
        if part == root:
            break
        if part.is_symlink():
            sys.exit(f'Claude package source must not be a symlink: {part}')
    if not source.is_file() or not stat.S_ISREG(source.stat().st_mode):
        sys.exit(f'Claude package source is not a regular file: {source}')

destination.mkdir(parents=True)
for source_relative, target_relative in entries:
    target = destination / target_relative
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(root / source_relative, target)
print(f'Built Claude package at {destination}')
PY
