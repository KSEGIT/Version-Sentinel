#!/usr/bin/env bash
VS_TEST_NAME="retry"
source "$(dirname "$0")/assert.sh"

source "$(dirname "$0")/../scripts/lib/retry.sh"

VS_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$VS_TMPDIR"' EXIT

# --- succeeds on first try ---
out=$(vs_retry 3 1 echo "hello")
assert_eq "hello" "$out" "succeeds immediately"

# --- retries then succeeds ---
COUNTER_FILE="$VS_TMPDIR/counter"
echo "0" > "$COUNTER_FILE"
cat > "$VS_TMPDIR/fail_twice.sh" <<'SCRIPT'
#!/usr/bin/env bash
count=$(cat "$1")
count=$((count + 1))
echo "$count" > "$1"
if [[ "$count" -lt 3 ]]; then exit 1; fi
echo "ok"
SCRIPT
chmod +x "$VS_TMPDIR/fail_twice.sh"

out=$(vs_retry 3 0.1 bash "$VS_TMPDIR/fail_twice.sh" "$COUNTER_FILE")
assert_eq "ok" "$out" "succeeds after retries"
count=$(cat "$COUNTER_FILE")
assert_eq "3" "$count" "ran 3 times total"

# --- exhausts retries → returns failure ---
echo "0" > "$COUNTER_FILE"
cat > "$VS_TMPDIR/always_fail.sh" <<'SCRIPT'
#!/usr/bin/env bash
count=$(cat "$1"); echo $((count + 1)) > "$1"; exit 1
SCRIPT
chmod +x "$VS_TMPDIR/always_fail.sh"
vs_retry 2 0.1 bash "$VS_TMPDIR/always_fail.sh" "$COUNTER_FILE"
rc=$?
assert_eq "1" "$rc" "returns failure after exhaustion"
count=$(cat "$COUNTER_FILE")
assert_eq "2" "$count" "attempted max_attempts times"

finish_test
