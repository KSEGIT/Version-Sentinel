#!/usr/bin/env bash
set -eu
DIR="$(cd "$(dirname "$0")" && pwd)"
python3 "$DIR/local_security_hooks_test.py"
