# Version Sentinel in Zed

Use `AGENTS.md`, `.agents/skills/`, and the bundled scripts for advisory version checks. The workflow is the same on every host: recommend upstream verification, report truthful evidence, and continue authorized work when a check cannot complete.

```bash
bash <version-sentinel-root>/scripts/check-versions.sh
bash <version-sentinel-root>/scripts/vs-record.sh <ecosystem> <pkg> <version> <source-url-or-intentional:reason>
```

Version Sentinel does not need Zed `always_confirm` rules for manifest edits or install commands. Remove Version Sentinel-specific rules from older setups if you want warning-only behavior. Keep unrelated host permissions according to your own preferences.

A missing check, audit failure, unsupported selector, private registry, or parser limitation is advisory. Preserve manifests and report limits; do not rewrite dependencies or demand recovery approval just to satisfy the tool. See [the advisory workflow](enforcement.md).
