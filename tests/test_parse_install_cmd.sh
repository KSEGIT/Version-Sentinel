#!/usr/bin/env bash
VS_TEST_NAME="parse-install-cmd"
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "$(dirname "$0")/assert.sh"
source "$SCRIPT_DIR/scripts/lib/parse-install-cmd.sh"

# npm install pkg (no version)
out=$(parse_install_cmd "npm install lodash")
assert_eq $'npm\tlodash\t__version_sentinel_unpinned__' "$out" "npm install <pkg> no version"

out=$(parse_install_cmd "npm install lodash@latest")
assert_eq $'npm\tlodash\t__version_sentinel_unpinned__' "$out" "npm install registry tag"

out=$(parse_install_cmd "npm install @scope/pkg")
assert_eq $'npm\t@scope/pkg\t__version_sentinel_unpinned__' "$out" "npm install scoped package without version"

out=$(parse_install_cmd "npm install lodash@beta")
assert_eq $'npm\tlodash\t__version_sentinel_unpinned__' "$out" "npm install arbitrary registry tag"

for _selector in '1.x' '1.X' '1.*' '1' '1.2' '^1.2.3' '~1.2.3' '>=1.x' '!=1.2.3' '1.x || 2.x' '1.2 || 2.3.4' '1.2 - 2.3.4' '1.2.3 || 2.3.4' '1.2.3 - 2.3.4'; do
  out=$(parse_install_cmd "npm install \"lodash@$_selector\"")
  assert_eq $'npm\tlodash\t__version_sentinel_unpinned__' "$out" "npm wildcard selector is unpinned: $_selector"
done

out=$(parse_install_cmd "npm install compat@npm:lodash@1.x")
assert_eq $'npm\tlodash\t__version_sentinel_unpinned__' "$out" "npm alias wildcard selector is unpinned"

out=$(parse_install_cmd "npm install compat@npm:@scope/pkg@1.2")
assert_eq $'npm\t@scope/pkg\t__version_sentinel_unpinned__' "$out" "scoped npm alias partial selector is unpinned"

# Every ecosystem must reject ranges, exclusions, wildcards, and compounds.
for _case in \
  $'npm install lodash@^1.2.3\tnpm\tlodash' \
  $'npm install lodash@!=1.2.3\tnpm\tlodash' \
  $'npm install lodash@1.*\tnpm\tlodash' \
  $'npm install "lodash@>=1.2.3 <2.0.0"\tnpm\tlodash' \
  $'pip install requests>=2.31.0\tpip\trequests' \
  $'pip install requests!=2.31.0\tpip\trequests' \
  $'pip install requests==2.*\tpip\trequests' \
  $'pip install "requests>=2,<3"\tpip\trequests' \
  $'poetry add flask@^3.0.0\tpip\tflask' \
  $'poetry add flask@!=3.0.0\tpip\tflask' \
  $'poetry add flask@3.*\tpip\tflask' \
  $'poetry add "flask@>=3,<4"\tpip\tflask' \
  $'cargo add serde@1.0.196\tcargo\tserde' \
  $'cargo add serde@^1.0.196\tcargo\tserde' \
  $'cargo add serde@!=1.0.196\tcargo\tserde' \
  $'cargo add serde@1.*\tcargo\tserde' \
  $'cargo add "serde@>=1,<2"\tcargo\tserde'; do
  IFS=$'\t' read -r _command _eco _pkg <<< "$_case"
  out=$(parse_install_cmd "$_command")
  expected=$(printf '%s\t%s\t%s' "$_eco" "$_pkg" "$VS_UNPINNED_VERSION")
  assert_eq "$expected" "$out" "non-exact registry selector is unpinned: $_command"
done

# Exact-selector operators are removed before sidecar lookup or recording.
for _case in \
  $'npm install lodash@=4.17.21\tnpm\tlodash\t4.17.21' \
  $'pip install requests==2.31.0\tpip\trequests\t2.31.0' \
  $'poetry add flask@=3.0.0\tpip\tflask\t3.0.0' \
  $'cargo add serde@=1.0.196\tcargo\tserde\t1.0.196'; do
  IFS=$'\t' read -r _command _eco _pkg _ver <<< "$_case"
  out=$(parse_install_cmd "$_command")
  assert_eq "$(printf '%s\t%s\t%s' "$_eco" "$_pkg" "$_ver")" "$out" "exact selector is normalized: $_command"
done

out=$(parse_install_cmd "pip install 'requests==2.31.0; python_version == \"3.*\"'")
assert_eq $'pip\trequests\t2.31.0' "$out" "wildcard in a PEP 508 environment marker does not unpin an exact requirement"

# Adjacent quoted and unquoted fragments form one shell word. The parser must
# join them too, or a syntactically valid install can bypass the hook.
for _case in \
  $'npm install lo"d"ash@4.17.21\tnpm\tlodash\t4.17.21' \
  $'pnpm add re"a"ct@18.2.0\tnpm\treact\t18.2.0' \
  $'yarn add re"a"ct@18.2.0\tnpm\treact\t18.2.0' \
  $'bun add re"a"ct@18.2.0\tnpm\treact\t18.2.0' \
  $'pip install requ"es"ts==2.31.0\tpip\trequests\t2.31.0' \
  $'poetry add fl"as"k@3.0.0\tpip\tflask\t3.0.0' \
  $'uv add requ"es"ts==2.31.0\tpip\trequests\t2.31.0' \
  $'cargo add se"rd"e@=1.0.196\tcargo\tserde\t1.0.196' \
  $'dotnet package add Newtonsoft."Json"@13.0.3\tcsproj\tNewtonsoft.Json\t13.0.3'; do
  IFS=$'\t' read -r _command _eco _pkg _ver <<< "$_case"
  out=$(parse_install_cmd "$_command")
  assert_eq "$(printf '%s\t%s\t%s' "$_eco" "$_pkg" "$_ver")" "$out" "shell word fragments are joined: $_command"
done

# Quoting a single package argument must not hide it. Quoted paths and URLs
# remain non-registry inputs.
out=$(parse_install_cmd 'npm install "lodash"')
assert_eq $'npm\tlodash\t__version_sentinel_unpinned__' "$out" "quoted npm bare package"

out=$(parse_install_cmd "npm install 'lodash@4.17.21'")
assert_eq $'npm\tlodash\t4.17.21' "$out" "quoted npm pinned package"

out=$(parse_install_cmd 'pip install "requests"')
assert_eq $'pip\trequests\t__version_sentinel_unpinned__' "$out" "quoted pip bare package"

out=$(parse_install_cmd "pip install 'requests==2.31.0'")
assert_eq $'pip\trequests\t2.31.0' "$out" "quoted pip pinned package"

for _c in 'npm install "./local-package"' \
          "npm install 'https://example.com/pkg.tgz'" \
          'pip install "./local-package"' \
          "pip install 'https://example.com/pkg.whl'"; do
  out=$(parse_install_cmd "$_c")
  assert_eq "" "$out" "quoted non-registry input is ignored: $_c"
done

# npm aliases resolve against their real registry target, not the local alias
# name, so sidecar checks cannot be laundered through an alias.
out=$(parse_install_cmd "npm install compat@npm:lodash")
assert_eq $'npm\tlodash\t__version_sentinel_unpinned__' "$out" "unversioned npm alias"

out=$(parse_install_cmd "npm install compat@npm:@scope/pkg")
assert_eq $'npm\t@scope/pkg\t__version_sentinel_unpinned__' "$out" "unversioned scoped npm alias"

out=$(parse_install_cmd "npm install compat@npm:lodash@4.17.21")
assert_eq $'npm\tlodash\t4.17.21' "$out" "versioned npm alias resolves real target"

out=$(parse_install_cmd "npm install compat@npm:@scope/pkg@1.2.3")
assert_eq $'npm\t@scope/pkg\t1.2.3' "$out" "versioned scoped npm alias resolves real target"

# npm install pkg@version
out=$(parse_install_cmd "npm install lodash@4.17.21")
assert_eq $'npm\tlodash\t4.17.21' "$out" "npm install <pkg>@<ver>"

# pnpm add with flag
out=$(parse_install_cmd "pnpm add react@18.2.0 --save-dev")
assert_eq $'npm\treact\t18.2.0' "$out" "pnpm add with flag"

# pip install pinned
out=$(parse_install_cmd "pip install requests==2.31.0")
assert_eq $'pip\trequests\t2.31.0' "$out" "pip install pinned"

# poetry add
out=$(parse_install_cmd "poetry add flask@=3.0.0")
assert_eq $'pip\tflask\t3.0.0' "$out" "poetry add"

# cargo add no version
out=$(parse_install_cmd "cargo add serde")
assert_eq $'cargo\tserde\t__version_sentinel_unpinned__' "$out" "cargo add no version"

# dotnet add package --version
out=$(parse_install_cmd "dotnet add package Newtonsoft.Json --version 13.0.3")
assert_eq $'csproj\tNewtonsoft.Json\t13.0.3' "$out" "dotnet add package --version"

# dotnet add package -v
out=$(parse_install_cmd "dotnet add package Serilog -v 3.1.1")
assert_eq $'csproj\tSerilog\t3.1.1' "$out" "dotnet add package -v"

# Non-install commands produce no output
out=$(parse_install_cmd "ls -la")
assert_eq "" "$out" "ls → no match"

# --- Command prefixes the shell strips before running the real command ------
# An agent that writes `timeout 30 <pm> install x` or `FOO=1 <pm> install x` is
# still installing x. These used to slip through: _parse_install_segment
# anchored on ^(npm|...) so any prefix defeated it entirely, and the package
# really did get installed. The hook `if` rules in hooks/hooks.json are shaped
# `Bash(*<mgr>*)` so the hook still spawns for these forms.

out=$(parse_install_cmd "FOO=bar npm install lodash@4.17.21")
assert_eq $'npm\tlodash\t4.17.21' "$out" "leading env assignment"

out=$(parse_install_cmd "NODE_ENV=production npm install lodash@4.17.21")
assert_eq $'npm\tlodash\t4.17.21' "$out" "leading env assignment (known-safe var)"

out=$(parse_install_cmd "A=1 B=2 npm install lodash@4.17.21")
assert_eq $'npm\tlodash\t4.17.21' "$out" "multiple leading env assignments"

out=$(parse_install_cmd "timeout 30 npm install lodash@4.17.21")
assert_eq $'npm\tlodash\t4.17.21' "$out" "timeout wrapper with duration"

out=$(parse_install_cmd "timeout 5s npm install lodash@4.17.21")
assert_eq $'npm\tlodash\t4.17.21' "$out" "timeout wrapper with suffixed duration"

out=$(parse_install_cmd "nice npm install lodash@4.17.21")
assert_eq $'npm\tlodash\t4.17.21' "$out" "nice wrapper"

out=$(parse_install_cmd "nice -n 10 npm install lodash@4.17.21")
assert_eq $'npm\tlodash\t4.17.21' "$out" "nice wrapper with flag"

out=$(parse_install_cmd "nohup pip install requests==2.31.0")
assert_eq $'pip\trequests\t2.31.0' "$out" "nohup wrapper"

out=$(parse_install_cmd "stdbuf -o0 cargo add serde")
assert_eq $'cargo\tserde\t__version_sentinel_unpinned__' "$out" "stdbuf wrapper with flag"

out=$(parse_install_cmd "command npm install lodash@4.17.21")
assert_eq $'npm\tlodash\t4.17.21' "$out" "command builtin"

out=$(parse_install_cmd "env FOO=1 npm install lodash@4.17.21")
assert_eq $'npm\tlodash\t4.17.21' "$out" "env wrapper carrying an assignment"

out=$(parse_install_cmd "sudo pip install requests==2.31.0")
assert_eq $'pip\trequests\t2.31.0' "$out" "sudo wrapper"

out=$(parse_install_cmd "time npm install lodash@4.17.21")
assert_eq $'npm\tlodash\t4.17.21' "$out" "time keyword"

out=$(parse_install_cmd "FOO=1 timeout 30 nice npm install lodash@4.17.21")
assert_eq $'npm\tlodash\t4.17.21' "$out" "assignment plus stacked wrappers"

out=$(parse_install_cmd "cd /tmp && FOO=1 npm install lodash@4.17.21")
assert_eq $'npm\tlodash\t4.17.21' "$out" "prefix inside a compound command"

# Stripping must not invent installs out of non-install commands.
out=$(parse_install_cmd "timeout 30 ls -la")
assert_eq "" "$out" "wrapper around a non-install command"

out=$(parse_install_cmd "command -v npm")
assert_eq "" "$out" "command -v lookup is not an install"

out=$(parse_install_cmd "echo timeout npm install lodash@4.17.21")
assert_eq "" "$out" "wrapper word inside an echo is not an install"

out=$(parse_install_cmd "FOO=bar ls -la")
assert_eq "" "$out" "assignment before a non-install command"


# Wrapper flags that take a separate operand, and the `--` terminator. The `--`
# case is the dangerous one: if the operand-consuming rule ran before the `--`
# check it would swallow the real command and reopen the bypass.
out=$(parse_install_cmd "sudo -u root pip install requests==2.31.0")
assert_eq $'pip\trequests\t2.31.0' "$out" "sudo with -u <user>"

out=$(parse_install_cmd "sudo -- npm install lodash@4.17.21")
assert_eq $'npm\tlodash\t4.17.21' "$out" "sudo with -- terminator"

out=$(parse_install_cmd "timeout -s KILL 30 npm install lodash@4.17.21")
assert_eq $'npm\tlodash\t4.17.21' "$out" "timeout with -s <signal> and duration"

out=$(parse_install_cmd "env -i FOO=1 npm install lodash@4.17.21")
assert_eq $'npm\tlodash\t4.17.21' "$out" "env -i with assignment"

# The cases above pass even if -i wrongly consumes a word, because the
# assignment stripper would have removed it anyway. These are the ones that
# actually exercise a no-operand flag sitting directly before the command:
# whether a flag takes an operand depends on the wrapper (-s does for timeout,
# not for sudo; -i takes none for sudo or env), so the stripper must decide by
# looking at the operand, not the flag.
out=$(parse_install_cmd "env -i npm install lodash@4.17.21")
assert_eq $'npm\tlodash\t4.17.21' "$out" "env -i directly before the command"

out=$(parse_install_cmd "sudo -i npm install lodash@4.17.21")
assert_eq $'npm\tlodash\t4.17.21' "$out" "sudo -i takes no operand"

out=$(parse_install_cmd "sudo -s pip install requests==2.31.0")
assert_eq $'pip\trequests\t2.31.0' "$out" "sudo -s takes no operand"

out=$(parse_install_cmd "sudo -e npm install lodash@4.17.21")
assert_eq $'npm\tlodash\t4.17.21' "$out" "sudo -e takes no operand"

out=$(parse_install_cmd "xargs -I {} npm install lodash@4.17.21")
assert_eq $'npm\tlodash\t4.17.21' "$out" "xargs -I {} consumes its operand"

out=$(parse_install_cmd "nohup timeout 60 nice -n 5 npm install lodash@4.17.21")
assert_eq $'npm\tlodash\t4.17.21' "$out" "stacked wrappers"

out=$(parse_install_cmd "xargs npm install lodash@4.17.21")
assert_eq $'npm\tlodash\t4.17.21' "$out" "bare xargs"

# A flag operand that merely looks like a package manager is not one.
out=$(parse_install_cmd "sudo -u npm whoami")
assert_eq "" "$out" "manager name as a flag operand is not an install"

out=$(parse_install_cmd "nice -n 10 make build")
assert_eq "" "$out" "wrapper around an unrelated build"

out=$(parse_install_cmd "git commit -m \"bump npm install docs\"")
assert_eq "" "$out" "manager words inside a commit message"

# --- Known limits, pinned so they stay visible rather than assumed covered ---
# The manager anchor is `^`, so anything in front of the manager that is not a
# stripped wrapper still defeats detection. Pre-existing gaps, NOT closed by
# _strip_cmd_prefix. `.venv/bin/pip install X` and `python -m pip install X` are
# the two most common pip invocations in practice, so this is the largest
# remaining hole in the guard.
out=$(parse_install_cmd "python -m pip install requests==2.31.0")
assert_eq "" "$out" "known limit: python -m pip is not detected"

out=$(parse_install_cmd "python3 -m pip install requests==2.31.0")
assert_eq "" "$out" "known limit: python3 -m pip is not detected"

out=$(parse_install_cmd ".venv/bin/pip install requests==2.31.0")
assert_eq "" "$out" "known limit: path-qualified pip is not detected"

out=$(parse_install_cmd "/usr/local/bin/npm install lodash@4.17.21")
assert_eq "" "$out" "known limit: path-qualified npm is not detected"

# Environment runners are NOT stripped, matching Claude Code's own
# wrapper list. `docker run ... <pm> install x` installs inside the container,
# not into this project, so it is out of scope rather than an oversight.
out=$(parse_install_cmd "docker run --rm node npm install lodash@4.17.21")
assert_eq "" "$out" "environment runners are deliberately not stripped"


# --- Over-stripping must never FABRICATE an install ------------------------
# Consuming `<flag> <word>` when the flag takes no operand eats the real command
# and parses what follows as an install that never happens. That is worse than
# missing one: `env -i true <pm> install <pkg>` runs `true`, installs nothing and
# exits 0, so auto-record.sh would record a version check for <pkg> and a genuine
# install of it would then be allowed with no check ever performed. Hence the
# per-wrapper table of flags that REQUIRE an operand.
out=$(parse_install_cmd "env -i true npm install evilpkg@9.9.9")
assert_eq "" "$out" "env -i does not take an operand, so true is the command"

out=$(parse_install_cmd "xargs -t echo npm install lodash@4.17.21")
assert_eq "" "$out" "xargs -t does not take an operand; echo is the command"

out=$(parse_install_cmd "env -0 grep npm install lodash@4.17.21 log.txt")
assert_eq "" "$out" "env -0 does not take an operand; grep is the command"

# Flags whose operand is OPTIONAL are deliberately absent from the table:
# guessing wrong here fabricates, guessing wrong the other way merely misses.
out=$(parse_install_cmd "xargs -i true npm install evilpkg@9.9.9")
assert_eq "" "$out" "xargs -i (optional operand) is not treated as taking one"

out=$(parse_install_cmd "sudo -h true npm install evilpkg@9.9.9")
assert_eq "" "$out" "sudo -h (optional operand) is not treated as taking one"

# timeout accepts fractional durations.
out=$(parse_install_cmd "timeout 1.5 npm install lodash@4.17.21")
assert_eq $'npm\tlodash\t4.17.21' "$out" "fractional timeout duration"

out=$(parse_install_cmd "timeout 0.5m npm install lodash@4.17.21")
assert_eq $'npm\tlodash\t4.17.21' "$out" "fractional suffixed timeout duration"

out=$(parse_install_cmd "stdbuf -o 0 cargo add serde")
assert_eq $'cargo\tserde\t__version_sentinel_unpinned__' "$out" "stdbuf -o with separate operand"

# Inputs and option operands that are not registry package names must not be
# converted into unpinned findings.
for _c in "pip install -r requirements.txt" \
          "pip install --requirement requirements.txt" \
          "pip install -e ." \
          "pip install ./local-package" \
          "pip install https://example.com/pkg.whl" \
          "npm install ./local-package" \
          "npm install local-package.tgz" \
          "npm install link:../local-package" \
          "npm install workspace:*" \
          "npm install git+https://example.com/repo.git" \
          "npm install github:user/repo" \
          "npm install https://example.com/pkg.tgz" \
          "poetry add ../local-package" \
          "poetry add git+https://example.com/repo.git" \
          "poetry add https://example.com/pkg.whl" \
          "cargo add --path ../local-crate" \
          "cargo add --git https://example.com/repo.git"; do
  out=$(parse_install_cmd "$_c")
  assert_eq "" "$out" "non-registry input is ignored: $_c"
done

out=$(parse_install_cmd "pip install --report report.json requests")
assert_eq $'pip\trequests\t__version_sentinel_unpinned__' "$out" "pip --report operand is not a package"

out=$(parse_install_cmd "cargo add --package app --manifest-path ./Cargo.toml serde@=1.0.196")
assert_eq $'cargo\tserde\t1.0.196' "$out" "cargo workspace option operands are not packages"

# Value-taking options must consume their operands. Boolean options and
# --option=value forms must not consume the following package.
out=$(parse_install_cmd "npm install --omit dev lodash@4.17.21")
assert_eq $'npm\tlodash\t4.17.21' "$out" "npm value option operand is not a package"

out=$(parse_install_cmd "pnpm add --filter app react@18.2.0")
assert_eq $'npm\treact\t18.2.0' "$out" "pnpm value option operand is not a package"

out=$(parse_install_cmd "pnpm add -w react@18.2.0")
assert_eq $'npm\treact\t18.2.0' "$out" "pnpm workspace-root boolean does not consume package"

out=$(parse_install_cmd "pnpm add --save-catalog react@18.2.0")
assert_eq $'npm\treact\t18.2.0' "$out" "pnpm save-catalog boolean does not consume package"

for _flag in -p -d -o -e --config --workspace; do
  out=$(parse_install_cmd "pnpm add $_flag react@18.2.0")
  assert_eq $'npm\treact\t18.2.0' "$out" "pnpm documented boolean does not consume package: $_flag"
done

out=$(parse_install_cmd "npm install --save lodash@4.17.21")
assert_eq $'npm\tlodash\t4.17.21' "$out" "npm save boolean does not consume package"

for _flag in -S -B -P -f --save-bundle --strict-allow-scripts --dangerously-allow-all-scripts; do
  out=$(parse_install_cmd "npm install $_flag lodash@4.17.21")
  assert_eq $'npm\tlodash\t4.17.21' "$out" "npm documented boolean does not consume package: $_flag"
done

for _flag in --no-package-lock --no-audit --no-bin-links --no-fund; do
  out=$(parse_install_cmd "npm install $_flag lodash@4.17.21")
  assert_eq $'npm\tlodash\t4.17.21' "$out" "npm negated boolean does not consume package: $_flag"
done

out=$(parse_install_cmd "npm install -DPE lodash@4.17.21")
assert_eq $'npm\tlodash\t4.17.21' "$out" "npm short boolean bundle does not consume package"

out=$(parse_install_cmd "npm install -wtools lodash@4.17.21")
assert_eq $'npm\tlodash\t4.17.21' "$out" "npm attached short value does not consume package"

out=$(parse_install_cmd "yarn add --mode skip-builds react@18.2.0")
assert_eq $'npm\treact\t18.2.0' "$out" "yarn value option operand is not a package"

out=$(parse_install_cmd "yarn add -F react@18.2.0")
assert_eq $'npm\treact\t18.2.0' "$out" "yarn fixed boolean does not consume package"

out=$(parse_install_cmd "bun add --backend copyfile react@18.2.0")
assert_eq $'npm\treact\t18.2.0' "$out" "bun value option operand is not a package"

for _flag in -y -p -f -E -a --save --quiet --no-verify --save-text-lockfile; do
  out=$(parse_install_cmd "bun add $_flag react@18.2.0")
  assert_eq $'npm\treact\t18.2.0' "$out" "bun documented boolean does not consume package: $_flag"
done

out=$(parse_install_cmd "npm install --omit=dev --save-dev lodash@4.17.21")
assert_eq $'npm\tlodash\t4.17.21' "$out" "npm equals option and boolean option preserve package"

out=$(parse_install_cmd "pip install --timeout 30 requests==2.31.0")
assert_eq $'pip\trequests\t2.31.0' "$out" "pip global value option operand is not a package"

out=$(parse_install_cmd "pip install -C builddir=tmp requests==2.31.0")
assert_eq $'pip\trequests\t2.31.0' "$out" "pip short value option operand is not a package"

out=$(parse_install_cmd "pip install -rrequirements.txt requests==2.31.0")
assert_eq $'pip\trequests\t2.31.0' "$out" "pip attached short value does not consume package"

out=$(parse_install_cmd "uv pip install --python-platform x86_64-unknown-linux-gnu requests==2.31.0")
assert_eq $'pip\trequests\t2.31.0' "$out" "uv value option operand is not a package"

out=$(parse_install_cmd "uv add --native-tls requests==2.31.0")
assert_eq $'pip\trequests\t2.31.0' "$out" "uv boolean option does not consume package"

out=$(parse_install_cmd "poetry add --python '^3.12' flask@3.0.0")
assert_eq $'pip\tflask\t3.0.0' "$out" "poetry value option operand is not a package"

out=$(parse_install_cmd "poetry add --editable flask@3.0.0")
assert_eq $'pip\tflask\t3.0.0' "$out" "poetry boolean option does not consume package"

out=$(parse_install_cmd "cargo add --color always serde@=1.0.196")
assert_eq $'cargo\tserde\t1.0.196' "$out" "cargo global value option operand is not a package"

out=$(parse_install_cmd "cargo add --base core serde@=1.0.196")
assert_eq $'cargo\tserde\t1.0.196' "$out" "cargo base option operand is not a package"

out=$(parse_install_cmd "cargo add -m ./Cargo.toml serde@=1.0.196")
assert_eq $'cargo\tserde\t1.0.196' "$out" "cargo short manifest-path operand is not a package"

out=$(parse_install_cmd "dotnet add package --framework net8.0 Newtonsoft.Json --version 13.0.3")
assert_eq $'csproj\tNewtonsoft.Json\t13.0.3' "$out" "dotnet value option operand is not a package"

out=$(parse_install_cmd "dotnet add package --interactive Newtonsoft.Json --version 13.0.3")
assert_eq $'csproj\tNewtonsoft.Json\t13.0.3' "$out" "dotnet boolean option does not consume package"

out=$(parse_install_cmd "dotnet add package --configfile NuGet.Config --verbosity quiet Newtonsoft.Json --version 13.0.3")
assert_eq $'csproj\tNewtonsoft.Json\t13.0.3' "$out" "dotnet compatibility option operands are not packages"

out=$(parse_install_cmd "dotnet package add Newtonsoft.Json --version 13.0.3")
assert_eq $'csproj\tNewtonsoft.Json\t13.0.3' "$out" "dotnet noun-first package add"

out=$(parse_install_cmd "dotnet package add Newtonsoft.Json@13.0.3")
assert_eq $'csproj\tNewtonsoft.Json\t13.0.3' "$out" "dotnet package-at-version syntax"

# npm accepts arbitrary config keys as command-line options. An option missing
# from the reviewed value/boolean table is ambiguous: block in the lenient
# pre-hook, and emit nothing in strict auto-record mode.
out=$(parse_install_cmd "npm install --future-option value lodash@4.17.21")
assert_eq $'__ambiguous_command__\tnpm option --future-option\t' "$out" "unknown npm option fails closed"

out=$(parse_install_cmd_strict "npm install --future-option value lodash@4.17.21")
assert_eq "" "$out" "unknown npm option cannot auto-record"

# Shell redirections and their filenames are not package arguments. A package
# after a redirection target must still be found.
for _c in \
  "npm install lodash@4.17.21 > install.log" \
  "npm install > install.log lodash@4.17.21" \
  "npm install lodash@4.17.21 >>install.log" \
  "npm install 2> errors.log lodash@4.17.21" \
  "npm install lodash@4.17.21 2>&1" \
  "npm install lodash@4.17.21 &>install.log" \
  "npm install &>install.log lodash@4.17.21" \
  "npm install 2>&1 lodash@4.17.21" \
  "npm install >& install.log lodash@4.17.21" \
  "npm install <& input.fd lodash@4.17.21" \
  "npm install 2>& 1 lodash@4.17.21" \
  "npm install 10> install.log lodash@4.17.21" \
  "npm install >| install.log lodash@4.17.21"; do
  out=$(parse_install_cmd "$_c")
  assert_eq $'npm\tlodash\t4.17.21' "$out" "npm shell redirection is ignored: $_c"
done


out=$(parse_install_cmd "pip install requests==2.31.0 2> errors.log")
assert_eq $'pip\trequests\t2.31.0' "$out" "pip redirection target is ignored"

out=$(parse_install_cmd "cargo add 2> errors.log serde@=1.0.196")
assert_eq $'cargo\tserde\t1.0.196' "$out" "cargo package after redirection target is preserved"


out=$(parse_install_cmd "env -P /usr/bin npm install lodash@4.17.21")
assert_eq $'npm\tlodash\t4.17.21' "$out" "env -P altpath (BSD)"

out=$(parse_install_cmd "xargs -J % npm install lodash@4.17.21")
assert_eq $'npm\tlodash\t4.17.21' "$out" "xargs -J replstr (BSD)"

out=$(parse_install_cmd "env -v true npm install evilpkg@9.9.9")
assert_eq "" "$out" "env -v takes no operand, so true is the command"


# `env -S` takes a COMMAND STRING as its operand, so the assumption that the
# word after an operand is the real command does not hold. All spellings must
# return an explicit ambiguity tuple so the blocking caller can fail closed.
for _c in "env -S npm install evilpkg@9.9.9" \
          "env -S true npm install evilpkg@9.9.9" \
          "env -Strue npm install evilpkg@9.9.9" \
          "env --split-string=true npm install evilpkg@9.9.9"; do
  out=$(parse_install_cmd "$_c")
  assert_eq $'__ambiguous_command__\tenv -S\t' "$out" "env -S is ambiguous: $_c"
done

# This parser is not quote-aware, so a quoted operand can hide a whole command.
out=$(parse_install_cmd 'sudo -p "x npm install evilpkg@1.0.0 " true')
assert_eq "" "$out" "quoted flag operand does not fabricate an install"

out=$(parse_install_cmd 'xargs -I "x npm install evilpkg@1.0.0 " true')
assert_eq "" "$out" "quoted replstr does not fabricate an install"

# sudo flags that unambiguously require an operand.
out=$(parse_install_cmd "sudo -D /app npm install lodash@4.17.21")
assert_eq $'npm\tlodash\t4.17.21' "$out" "sudo -D/--chdir"

out=$(parse_install_cmd "sudo -R /chroot npm install lodash@4.17.21")
assert_eq $'npm\tlodash\t4.17.21' "$out" "sudo -R/--chroot"

# --- strict mode: no prefix stripping at all ------------------------------
# auto-record.sh uses this. Over-detection there writes a check for a package
# nobody verified, which switches the guard off for it; over-detection in the
# blocking path only costs a false block. So the dangerous path does not guess.
out=$(parse_install_cmd_strict "npm install lodash@4.17.21")
assert_eq $'npm\tlodash\t4.17.21' "$out" "strict still parses a bare install"

for _c in 'echo foo\; npm install evilpkg@9.9.9' \
          'echo foo\| npm install evilpkg@9.9.9' \
          'echo foo\& npm install evilpkg@9.9.9'; do
  out=$(parse_install_cmd_strict "$_c")
  assert_eq "" "$out" "strict does not split an escaped shell separator: $_c"
done

out=$(parse_install_cmd_strict 'npm install lodash\@4.17.21')
assert_eq $'npm\tlodash\t4.17.21' "$out" "escaped ordinary character keeps the package visible"

for _c in "sudo npm install evilpkg@9.9.9" \
          "timeout 30 npm install evilpkg@9.9.9" \
          "env -S npm install evilpkg@9.9.9" \
          "env -S true npm install evilpkg@9.9.9" \
          "FOO=bar npm install evilpkg@9.9.9"; do
  out=$(parse_install_cmd_strict "$_c")
  assert_eq "" "$out" "strict does not strip prefixes: $_c"
done


# `-S` means a command string for env, but for sudo it means read-the-password-
# from-stdin and takes no operand, so the next word IS the command.
# `echo pw | sudo -S <pm> install <pkg>` is a standard idiom; bailing on it
# skipped a real install.
out=$(parse_install_cmd "sudo -S npm install lodash@4.17.21")
assert_eq $'npm\tlodash\t4.17.21' "$out" "sudo -S is not env -S"

out=$(parse_install_cmd "sudo -Sk npm install lodash@4.17.21")
assert_eq $'npm\tlodash\t4.17.21' "$out" "sudo -Sk clustered"

out=$(parse_install_cmd "sudo -H -S npm install lodash@4.17.21")
assert_eq $'npm\tlodash\t4.17.21' "$out" "sudo -H -S"


# An env-assignment value may be quoted and contain spaces. The value class must
# understand quoting, or the stripper stops mid-value and the manager anchor
# fails -- a real bypass, since the `if` rule still fires and the hook then
# waves the install through.
out=$(parse_install_cmd "CFLAGS='-O2 -g' pip install requests==2.31.0")
assert_eq $'pip\trequests\t2.31.0' "$out" "single-quoted assignment value with a space"

out=$(parse_install_cmd 'PIP_INDEX_URL="https://a b" pip install requests==2.31.0')
assert_eq $'pip\trequests\t2.31.0' "$out" "double-quoted assignment value with a space"

out=$(parse_install_cmd "A='x y' B='p q' npm install lodash@4.17.21")
assert_eq $'npm\tlodash\t4.17.21' "$out" "several quoted assignment values"

out=$(parse_install_cmd "NODE_OPTIONS='--max-old-space-size=4096' npm install lodash@4.17.21")
assert_eq $'npm\tlodash\t4.17.21' "$out" "quoted value without spaces still works"

# TAB separation: _parse_install_segment anchors on [[:space:]]+, and the hook
# rules are shaped `Bash(*<mgr>*)` with no trailing space so the gate fires for
# it too. Tightening the parser to [ ]+ would pass CI while reopening that
# bypass, so pin the behaviour the rule shape exists for.
out=$(parse_install_cmd "$(printf 'npm\tinstall\tlodash@4.17.21')")
assert_eq $'npm\tlodash\t4.17.21' "$out" "TAB-separated npm install"

out=$(parse_install_cmd "$(printf 'pip\tinstall\trequests==2.31.0')")
assert_eq $'pip\trequests\t2.31.0' "$out" "TAB-separated pip install"

out=$(parse_install_cmd "npm  install  lodash@4.17.21")
assert_eq $'npm\tlodash\t4.17.21' "$out" "doubled spaces"

# Known limits: nested command contexts are not split into segments, so the rule
# matches the text, the hook fires, and then finds nothing.
out=$(parse_install_cmd 'echo $(npm install evilpkg@9.9.9)')
assert_eq "" "$out" "known limit: install inside \$() is not detected"

out=$(parse_install_cmd "timeout 30 bash -c 'npm install evilpkg@1.0.0'")
assert_eq "" "$out" "known limit: install inside bash -c is not detected"


finish_test
