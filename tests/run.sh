#!/usr/bin/env bash
# Discover and run every tests/test_*.sh. Each test sets VS_TEST_NAME and sources assert.sh.
set -u
cd "$(dirname "$0")"

total=0
failed=0
for t in test_*.sh; do
  [[ -f "$t" ]] || continue
  total=$((total + 1))
  if ! bash "$t"; then
    failed=$((failed + 1))
  fi
done

echo
echo "=== Integration smoke ==="
if bash integration/smoke.sh; then
  total=$((total + 1))
else
  total=$((total + 1))
  failed=$((failed + 1))
fi

echo
echo "-----"
echo "Total: $total, Failed: $failed"
[[ "$failed" -eq 0 ]]
