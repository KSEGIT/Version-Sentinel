#!/usr/bin/env bash
# End-to-end smoke test. Runs hook scripts directly against realistic fixtures.
set -u

echo "=== version-sentinel integration smoke ==="

VS_TMPDIR=$(mktemp -d)
cleanup() { rm -rf "$VS_TMPDIR"; }
trap cleanup EXIT

SCRIPT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"

cd "$VS_TMPDIR"
cat > package.json <<'EOF'
{ "name": "demo", "version": "1.0.0", "dependencies": { "express": "4.19.2" } }
EOF

# --- 1. Manifest edit adds lodash → should block ---
input=$(cat <<EOF
{
  "tool_name": "Edit",
  "tool_input": {
    "file_path": "$VS_TMPDIR/package.json",
    "old_string": "\"express\": \"4.19.2\"",
    "new_string": "\"express\": \"4.19.2\", \"lodash\": \"4.17.21\"",
    "replace_all": false
  }
}
EOF
)
echo "[1/4] Edit adds lodash (expect exit 2)"
echo "$input" | bash "$SCRIPT_DIR/scripts/detect-manifest-edit.sh" 2>/tmp/smoke1_$$.err
rc=$?
[[ "$rc" -eq 2 ]] || { echo "FAIL: expected exit 2, got $rc"; exit 1; }
grep -q "lodash" /tmp/smoke1_$$.err || { echo "FAIL: stderr missing lodash"; exit 1; }
echo "  OK"

# --- 2. /vs-record the check ---
echo "[2/4] /vs-record"
bash "$SCRIPT_DIR/scripts/vs-record.sh" npm lodash 4.17.21 "https://www.npmjs.com/package/lodash" \
  || { echo "FAIL: vs-record"; exit 1; }
echo "  OK"

# --- 3. Retry edit → should pass ---
echo "[3/4] Retry edit (expect exit 0)"
echo "$input" | bash "$SCRIPT_DIR/scripts/detect-manifest-edit.sh" 2>/tmp/smoke2_$$.err
rc=$?
[[ "$rc" -eq 0 ]] || { echo "FAIL: expected exit 0 after record, got $rc"; cat /tmp/smoke2_$$.err; exit 1; }
echo "  OK"

# --- 4. Bash install cmd without record → block ---
echo "[4/4] Bash npm install requests@2.31.0 (expect exit 2)"
echo '{"tool_name":"Bash","tool_input":{"command":"npm install requests@2.31.0"}}' \
  | bash "$SCRIPT_DIR/scripts/detect-install-cmd.sh" 2>/tmp/smoke3_$$.err
rc=$?
[[ "$rc" -eq 2 ]] || { echo "FAIL: bash install not blocked, got $rc"; exit 1; }
grep -q "requests" /tmp/smoke3_$$.err || { echo "FAIL: stderr missing requests"; exit 1; }
echo "  OK"

rm -f /tmp/smoke1_$$.err /tmp/smoke2_$$.err /tmp/smoke3_$$.err

echo "=== ALL SMOKE TESTS PASS ==="
