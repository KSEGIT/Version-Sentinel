#!/usr/bin/env bash
VS_TEST_NAME="parse-install-cmd"
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "$(dirname "$0")/assert.sh"
source "$SCRIPT_DIR/scripts/lib/parse-install-cmd.sh"

# npm install pkg (no version)
out=$(parse_install_cmd "npm install lodash")
assert_eq $'npm\tlodash\t' "$out" "npm install <pkg> no version"

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
out=$(parse_install_cmd "poetry add flask@^3.0.0")
assert_eq $'pip\tflask\t3.0.0' "$out" "poetry add"

# cargo add no version
out=$(parse_install_cmd "cargo add serde")
assert_eq $'cargo\tserde\t' "$out" "cargo add no version"

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
# `Bash(*<mgr> *)` so the hook still spawns for these forms.

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
assert_eq $'cargo\tserde\t' "$out" "stdbuf wrapper with flag"

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

# Known limit: environment runners are NOT stripped, matching Claude Code's own
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
assert_eq "" "$out" "env -i does not take an operand; `true` is the command"

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
assert_eq $'cargo\tserde\t' "$out" "stdbuf -o with separate operand"


finish_test
