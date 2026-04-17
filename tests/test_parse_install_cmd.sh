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

finish_test
