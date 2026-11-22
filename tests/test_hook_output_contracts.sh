#!/usr/bin/env bash
# Validate public output against the host's independently published wire schemas.
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
python3 "$ROOT/tests/hook_output_contracts_test.py"
