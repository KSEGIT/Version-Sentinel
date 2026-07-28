# Version Sentinel

This workspace uses version-sentinel: dependency edits and install commands are blocked (via workspace hooks) until the target version is verified against its upstream registry and recorded.

## When a tool call is BLOCKED with "version-sentinel"

1. Look up the latest version of the package on its upstream registry:
   - npm → npmjs.com
   - pip / pyproject → pypi.org
   - cargo → crates.io
   - csproj → nuget.org
2. Record the check by running in the terminal:
   `bash scripts/vs-record.sh <ecosystem> <pkg> <version> <source-url>`
   The source must be an `http(s)://` URL you actually saw, or `intentional: <reason>` for deliberate pins.
3. Retry the original edit or install — the hook will see the fresh record and let it through.

## Intentional pins

To deliberately install a non-latest version (CVE mitigation, compatibility), record with `intentional: <reason>` as the source. These show as `intentional-pin`, not `DRIFT`, in audits.

## Audit

Run `bash scripts/check-versions.sh` before tagging a release. It scans `package.json`, `requirements*.txt`, `constraints*.txt`, `pyproject.toml`, `Cargo.toml`, `*.csproj`, `*.fsproj`, and `*.vbproj` and reports drift without blocking.

## Escape hatch

Set `VS_DISABLE=1` in the environment to disable blocking for a session (throwaway work only, with the user's awareness).
