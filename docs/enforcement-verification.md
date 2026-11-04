# Mandatory audit verification

Verified on 2026-11-03 against the feature branch. Routine tests use canonical-registry HTTP fixtures, not production installs.

- TDD reproduced the original patch-only, multi-file, URL-only recording, missing-manifest, and failed-audit bypasses before implementation.
- Independent component and whole-change reviews reproduced further gaps in build requirements, ecosystem manifest selection, directory overrides, direct resolvers, override selectors, and Windows CRLF handling. Regression tests cover the fixes.
- `bash tests/run.sh` runs the full shell test suite and integration smoke. ShellCheck at error severity, `bash -n`, Python compilation, JSON hook validation, and whitespace checks form the static checks. CI also covers Linux, macOS, and Windows; local validation alone does not claim those remote jobs passed.

## Live dogfood

The candidate audited Version Sentinel's `site` directory online: four declared packages, two matching latest and two newer releases reported as `DRIFT`. It completed without upgrading dependencies. The repository-root audit correctly blocked on the intentionally broken requirements include `tests/fixtures/other.txt`; that failure was not counted as completion.

A disposable project exercised the candidate scripts with real upstream access:

1. Bare install blocked before audit.
2. Startup completed and an unrecorded package addition still blocked.
3. A fabricated source was rejected.
4. The recorder fetched canonical npm metadata for `is-number@7.0.0` and recorded successful version-existence evidence.
5. The same proposed edit passed.
6. Writing the checked manifest invalidated the earlier audit; another bare install blocked.
7. A new audit completed and the exact-version dry-run command passed its candidate pre-tool check.

Separate live requests verified PyPI, crates.io, and NuGet response shapes and exact version existence. A disposable missing-manifest fixture blocked startup and silent recreation, allowed read-only inspection, accepted simulated test consent for that exact missing path, allowed the approved empty manifest, and completed its subsequent audit. This tested the consent interface; it does not imply an agent may manufacture consent for a real project.

## Host dispatch and activation limit

An actual Codex `exec_command` probe ran `npm install react@0.0.0-version-sentinel-hook-probe --dry-run --ignore-scripts --package-lock=false --offline`. The currently installed PreToolUse hook rejected it before command execution. No package was installed.

Candidate hook definitions were separately executed from copied plugin paths with spaces, and candidate scripts were exercised with realistic platform payloads. The candidate is not yet installed or trusted in the active session. The host-dispatch probe therefore proves dispatch of the installed hook, not activation of this branch. No installed plugin cache or persisted trust was edited.

After review and normal plugin update, Daniel must open `/hooks` (or Settings > Hooks), review and trust the changed Version Sentinel hooks, then start a new session and repeat the startup and blocked-install probes. That host activation step remains outside this source PR. Arbitrary shell/Python file writes, local evidence tampering, private registries, and unsupported dependency selectors remain the documented limits in [enforcement.md](enforcement.md).

The first Windows CI run exposed JSON paths that Git Bash does not translate for native Python, backslash-only Python-to-Bash script arguments, and tests that compared POSIX spellings with native paths or used copied MSYS symlinks. Follow-up checks map MSYS JSON paths through `cygpath`, preserve project containment, use portable inventory keys, and exercise native symlinks and the original Bash executable. The shared helper has explicit Windows path boundary tests.

A fast native Windows boundary probe then proved that the bare `bash` executable selected Windows' WSL launcher, which failed because no distribution was installed. The same validation passed through the absolute Git Bash executable resolved from PATH. Manifest subprocesses now use that explicit executable, and the CI preflight checks this boundary before the full Windows suite.
