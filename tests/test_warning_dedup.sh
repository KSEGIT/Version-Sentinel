#!/usr/bin/env bash
set -eu
DIR="$(cd "$(dirname "$0")" && pwd)"
python3 "$DIR/warning_dedup_test.py"
