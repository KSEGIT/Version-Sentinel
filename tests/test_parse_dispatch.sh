#!/usr/bin/env bash
VS_TEST_NAME="parse-dispatch"
FIXTURES="$(dirname "$0")/fixtures"
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "$(dirname "$0")/assert.sh"
source "$SCRIPT_DIR/scripts/lib/parse-manifest.sh"

# Dispatch by path
eco=$(ecosystem_for_path "/proj/package.json")
assert_eq "npm" "$eco" "npm dispatch"

eco=$(ecosystem_for_path "/proj/requirements.txt")
assert_eq "pip" "$eco" "pip dispatch"

eco=$(ecosystem_for_path "/proj/requirements-dev.txt")
assert_eq "pip" "$eco" "pip glob dispatch"

eco=$(ecosystem_for_path "/proj/pyproject.toml")
assert_eq "pyproject" "$eco" "pyproject dispatch"

eco=$(ecosystem_for_path "/proj/Cargo.toml")
assert_eq "cargo" "$eco" "cargo dispatch"

eco=$(ecosystem_for_path "/proj/Foo.csproj")
assert_eq "csproj" "$eco" "csproj dispatch"

eco=$(ecosystem_for_path "/proj/README.md")
assert_eq "" "$eco" "unrelated file → empty"

# parse_by_path routes to correct parser
out=$(parse_manifest_by_path "$FIXTURES/package.json" | wc -l | tr -d ' ')
assert_eq "5" "$out" "npm parser produces 5 lines"

# diff_manifest_sets: added + changed + unchanged
pre=$(printf 'lodash\t4.17.20\njest\t29.7.0\n')
post=$(printf 'lodash\t4.17.21\njest\t29.7.0\nexpress\t4.19.2\n')
out=$(diff_manifest_sets "$pre" "$post" | sort)
expected=$(printf 'added\texpress\t4.19.2\nchanged\tlodash\t4.17.21\n' | sort)
assert_eq "$expected" "$out" "diff: added + changed, removed/unchanged ignored"

finish_test
