# Version Sentinel

Version Sentinel gives dependency warnings only. Hooks always return status 0 and allow the tool call. Missing or failed audits, stale checks, unsupported syntax, private registries, missing prerequisites, and missing or invalid manifests never become permission gates. Continue the user-authorized task and report the relevant limitation. Do not ask for approval merely because Version Sentinel warns.

## Recommended version checks

Look up the intended version on its upstream registry when practical:

- npm: `https://www.npmjs.com/package/<pkg>`
- pip / pyproject: `https://pypi.org/project/<pkg>/`
- Cargo: `https://crates.io/crates/<pkg>`
- NuGet: `https://www.nuget.org/packages/<pkg>`

Record a successful check from the project directory:

```bash
bash <plugin-root>/scripts/vs-record.sh <ecosystem> <pkg> <version> <source-url-or-intentional:reason>
```

Use a canonical `https://` source you actually consulted, or `intentional:<reason>` for a deliberate older pin. The recorder makes its own online check. Report failures truthfully; do not claim verification when it failed. Exact versions make checks reproducible, but floating versions and versionless installs remain allowed.

## Audits and limitations

Startup only suggests an optional explicit audit; it makes no registry requests.

Run `bash <plugin-root>/scripts/check-versions.sh` to compare supported manifests against upstream releases. Report the exit status and diagnostics. Direct audit and recorder commands can return nonzero when validation fails; that reports their result and does not prohibit other work.

Preserve valid dependencies, overrides, selectors, and sources when the parser cannot understand them. Do not rewrite a manifest merely to satisfy the tool. Resolve missing or invalid manifests within the user's authorized task using repository evidence. Normal approval rules for destructive changes still apply separately; no recovery-consent command is needed to continue.

Checks are stored in `.version-sentinel/checks.json` and audit evidence in `.version-sentinel/audit.json`. Evidence expires after the configured freshness window (24 hours by default). Local paths, git sources, workspace dependencies, and private registries are outside public registry verification. A NuGet `PackageReference` without `Version` may use Central Package Management.

`VS_DISABLE=1` disables hook warnings. It is not needed to continue work. See the advisory workflow in `docs/enforcement.md` for scope and limits.
