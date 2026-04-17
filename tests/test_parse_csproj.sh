#!/usr/bin/env bash
VS_TEST_NAME="parse-csproj"
FIXTURES="$(dirname "$0")/fixtures"
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "$(dirname "$0")/assert.sh"
source "$SCRIPT_DIR/scripts/lib/parse-manifest.sh"

out=$(parse_csproj "$FIXTURES/Demo.csproj" | sort)
expected=$(printf '%s\n' \
  "Dapper	2.1.28" \
  "Newtonsoft.Json	13.0.3" \
  "Serilog	3.1.1" | sort)
assert_eq "$expected" "$out" "csproj PackageReference parsing"

finish_test
