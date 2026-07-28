# version-sentinel (Gemini CLI extension)

This extension hard-blocks dependency additions, bumps, and downgrades until a
fresh, source-cited version check is recorded. It exists to stop the model from
shipping a hallucinated or stale package version remembered from training data.

## How it works

1. You try to edit a dependency manifest (`write_file` / `replace` on
   `package.json`, `requirements*.txt`, `pyproject.toml`, `Cargo.toml`,
   `*.csproj`, ...) or run an install command via `run_shell_command`
   (`npm install`, `pip install`, `cargo add`, `dotnet add package`, ...).
2. A `BeforeTool` hook fires and exits 2 — the tool call is blocked and the
   hook's stderr explains why:
   ```text
   BLOCKED: version-sentinel.
   Package: lodash (npm). Version: 4.17.21.
   No fresh version check on record.
   ```
3. To unblock: look up the real latest version on the upstream registry
   (npmjs.com, pypi.org, crates.io, nuget.org), then record the check:
   ```bash
   /vs-record npm lodash 4.17.21 https://www.npmjs.com/package/lodash
   ```
   Then retry the original edit or install — the hook finds the fresh entry
   and lets it through.

## Intentional pins

Pinning an old version on purpose is fine — record it with a reason instead
of a URL:

```bash
/vs-record npm pkg 1.0.0 "intentional: CVE fix deferred pending audit"
```

Intentional pins unblock the hook and show as `intentional-pin` (not `DRIFT`)
in audits.

## Auditing drift

Run `/check-versions` to scan manifests within 4 directory levels of the workspace
and compare each pinned version against the latest upstream release. Advisory only
— never blocks.

## Escape hatch

Set `VS_DISABLE=1` in the environment to make every version-sentinel hook a
no-op (useful for throwaway sessions).

## Prerequisites

`bash`, `jq`, `curl`, and `python3` (3.11+, for `tomllib`) on `PATH`.

Recorded checks live in `<workspace>/.version-sentinel/checks.json`
(auto-gitignored on first write).
