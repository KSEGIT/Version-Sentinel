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

tmp=$(mktemp --suffix=.csproj 2>/dev/null || mktemp)
printf '%s\n' '<Project><ItemGroup><PackageReference Include="Polly" Version="*" /><PackageReference Include="Central.Versioned" /></ItemGroup></Project>' > "$tmp"
out=$(parse_csproj "$tmp")
assert_eq $'Polly\t__version_sentinel_unpinned__' "$out" "csproj floating Version is unpinned; omitted Version may use central management"
rm -f "$tmp"

finish_test
