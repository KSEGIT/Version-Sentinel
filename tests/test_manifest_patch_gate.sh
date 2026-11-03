#!/usr/bin/env bash
# Guards against patch-only/multi-file bypasses and unsafe recovery.
VS_TEST_NAME="manifest-patch-gate"
TESTS_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$TESTS_DIR/assert.sh"
source "$TESTS_DIR/registry-fixture.sh"
SCRIPTS="$(cd "$TESTS_DIR/../scripts" && pwd)"
VS_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$VS_TMPDIR"' EXIT
cd "$VS_TMPDIR" || exit 1
registry_fixture_setup
printf '{"name":"demo","dependencies":{}}\n' > package.json

probe_patch() {
  jq -nc --arg cwd "$VS_TMPDIR" --arg patch "$1" \
    '{cwd:$cwd,tool_name:"apply_patch",tool_input:{patch:$patch}}' \
    | bash "$SCRIPTS/detect-manifest-edit.sh" 2>&1
}

patch=$'*** Begin Patch\n*** Update File: package.json\n@@\n-{"name":"demo","dependencies":{}}\n+{"name":"demo","dependencies":{"lodash":"4.17.21"}}\n*** End Patch'
result=$(probe_patch "$patch"; echo "exit=$?")
assert_contains "$result" "BLOCKED" "patch-only dependency addition blocks"
assert_contains "$result" "exit=2" "patch-only addition exits 2"

multi=$'*** Begin Patch\n*** Add File: README.md\n+hello\n*** Update File: package.json\n@@\n-{"name":"demo","dependencies":{}}\n+{"name":"demo","dependencies":{"lodash":"4.17.21"}}\n*** End Patch'
result=$(probe_patch "$multi"; echo "exit=$?")
assert_contains "$result" "exit=2" "multiple paths cannot hide dependency addition"

result=$(probe_patch $'*** Begin Patch\n*** Delete File: package.json\n*** End Patch'; echo "exit=$?")
assert_contains "$result" "exit=2" "manifest deletion blocks"
assert_contains "$result" "Daniel" "deletion asks user before recovery"

result=$(probe_patch $'*** Begin Patch\n*** Update File: package.json\n*** Move to: hidden.json\n*** End Patch'; echo "exit=$?")
assert_contains "$result" "exit=2" "renaming required manifest away blocks"

metadata=$'*** Begin Patch\n*** Update File: package.json\n@@\n-{"name":"demo","dependencies":{}}\n+{"name":"renamed","dependencies":{}}\n*** End Patch'
result=$(probe_patch "$metadata"; echo "exit=$?")
assert_contains "$result" "exit=0" "metadata-only patch permits read-only recovery work"

result=$(printf '%s' '{bad json' | bash "$SCRIPTS/detect-manifest-edit.sh" 2>&1; echo "exit=$?")
assert_contains "$result" "exit=2" "malformed payload fails closed"

result=$(jq -nc '{tool_name:"Write",tool_input:{file_path:"package.json",content:{dependencies:{}}}}' \
  | bash "$SCRIPTS/detect-manifest-edit.sh" 2>&1; echo "exit=$?")
assert_contains "$result" "exit=2" "non-string manifest content fails closed"

result=$(jq -nc '{tool_name:"Write",tool_input:{file_path:"missing/package.json",content:"{}"}}' \
  | bash "$SCRIPTS/detect-manifest-edit.sh" 2>&1; echo "exit=$?")
assert_contains "$result" "exit=2" "missing manifest cannot silently be created"
assert_contains "$result" "Daniel" "missing manifest requests user consent"

result=$(probe_patch $'*** Begin Patch\n*** Update File: package.json\n@@\n-does not match\n+{}\n*** End Patch'; echo "exit=$?")
assert_contains "$result" "exit=2" "unreconstructable relevant patch fails closed"

result=$(probe_patch $'*** Begin Patch\n*** Add File: README.md\n+hello\n*** End Patch'; echo "exit=$?")
assert_contains "$result" "exit=0" "unrelated patch stays usable without audit"

# A hidden second entry must not make a multi-file Write pass.
result=$(jq -nc '{tool_name:"Write",tool_input:{files:[
  {file_path:"README.md",content:"safe"},
  {file_path:"package.json",content:"{\"dependencies\":{\"lodash\":\"4.17.21\"}}"}
]}}' | bash "$SCRIPTS/detect-manifest-edit.sh" 2>&1; echo "exit=$?")
assert_contains "$result" "exit=2" "multi-file Write inspects every manifest"

result=$(jq -nc '{tool_name:"Bash",tool_input:{command:"cat package.json"}}' \
  | bash "$SCRIPTS/detect-manifest-edit.sh" 2>&1; echo "exit=$?")
assert_contains "$result" "exit=0" "known read-only terminal calls stay usable"

result=$(jq -nc '{tool_name:"unknown_edit",tool_input:{file_path:"package.json",content:"{}"}}' \
  | bash "$SCRIPTS/detect-manifest-edit.sh" 2>&1; echo "exit=$?")
assert_contains "$result" "exit=2" "unsupported relevant tool shape blocks"

result=$(jq -nc '{tool_name:"Write",tool_input:{file_path:"README.md",path:"package.json",content:"{\"dependencies\":{\"lodash\":\"4.17.21\"}}"}}' \
  | bash "$SCRIPTS/detect-manifest-edit.sh" 2>&1; echo "exit=$?")
assert_contains "$result" "exit=2" "conflicting path aliases cannot hide a manifest"

result=$(jq -nc '{tool_name:"Write",tool_input:{file_path:"package.json",content:"{\"dependencies\":{\"lodash\":\"4.17.21\"}}",files:[{file_path:"README.md",content:"safe"}]}}' \
  | bash "$SCRIPTS/detect-manifest-edit.sh" 2>&1; echo "exit=$?")
assert_contains "$result" "exit=2" "mixed multi-file and single-file payload fails closed"

result=$(probe_patch $'*** Begin Patch\n*** Update File: package.json \n@@\n-{"name":"demo","dependencies":{}}\n+{"name":"demo","dependencies":{"lodash":"4.17.21"}}\n*** End Patch'; echo "exit=$?")
assert_contains "$result" "exit=2" "patch header whitespace cannot hide a manifest"

result=$(jq -nc '{tool_name:"Write",tool_input:{file_path:"package.json",content:"{\"dependencies\":{\"local\":\"file:../local\"}}"}}' \
  | bash "$SCRIPTS/detect-manifest-edit.sh" 2>&1; echo "exit=$?")
assert_contains "$result" "exit=2" "local dependency work still requires startup audit"

printf '{"dependencies":{"lodash":"^4.17.21"}}\n' > package.json
bash "$SCRIPTS/check-versions.sh" >/dev/null 2>&1
result=$(jq -nc '{tool_name:"Write",tool_input:{file_path:"package.json",content:"{\"dependencies\":{\"lodash\":\"~4.17.21\"}}"}}' \
  | bash "$SCRIPTS/detect-manifest-edit.sh" 2>&1; echo "exit=$?")
assert_contains "$result" "exit=2" "selector changes need online verification even with same lower bound"

mkdir -p a/b/c/d
printf '{"dependencies":{}}\n' > a/b/c/d/package.json
bash "$SCRIPTS/check-versions.sh" >/dev/null 2>&1
bash "$SCRIPTS/vs-record.sh" npm lodash 4.17.21 https://www.npmjs.com/package/lodash >/dev/null
result=$(jq -nc '{tool_name:"Write",tool_input:{file_path:"a/b/c/d/package.json",content:"{\"dependencies\":{\"lodash\":\"4.17.21\"}}"}}' \
  | bash "$SCRIPTS/detect-manifest-edit.sh" 2>&1; echo "exit=$?")
assert_contains "$result" "exit=2" "an unaudited deep manifest cannot borrow root audit evidence"

python3 -c 'import os,pathlib; os.symlink("package.json", "alias.txt"); assert pathlib.Path("alias.txt").is_symlink()' || exit 1
result=$(jq -nc '{tool_name:"Write",tool_input:{file_path:"alias.txt",content:"{\"dependencies\":{\"unverified\":\"1.0.0\"}}"}}' \
  | bash "$SCRIPTS/detect-manifest-edit.sh" 2>&1; echo "exit=$?")
assert_contains "$result" "exit=2" "symlink alias cannot hide a registry manifest"

result=$(jq -nc '{session_id:"new-session",tool_name:"Write",tool_input:{file_path:"package.json",content:"{\"dependencies\":{\"lodash\":\"4.17.21\",\"other\":\"1.0.0\"}}"}}' \
  | bash "$SCRIPTS/detect-manifest-edit.sh" 2>&1; echo "exit=$?")
assert_contains "$result" "Startup dependency audit" "hook session identity reaches audit gate"

# The unchanged baseline must stay usable, while an extra addition must not
# conceal another dependency's selector-only change.
jq '.entries |= map(select(.pkg != "lodash"))' .version-sentinel/checks.json > checks.tmp
mv checks.tmp .version-sentinel/checks.json
bash "$SCRIPTS/vs-record.sh" npm other 1.0.0 "intentional: fixture compatibility" >/dev/null
result=$(jq -nc '{tool_name:"Write",tool_input:{file_path:"package.json",content:"{\"dependencies\":{\"lodash\":\"^4.17.21\",\"other\":\"1.0.0\"}}"}}' \
  | bash "$SCRIPTS/detect-manifest-edit.sh" 2>&1; echo "exit=$?")
assert_contains "$result" "exit=0" "unchanged baseline dependencies do not need unrelated records"
result=$(jq -nc '{tool_name:"Write",tool_input:{file_path:"package.json",content:"{\"dependencies\":{\"lodash\":\"~4.17.21\",\"other\":\"1.0.0\"}}"}}' \
  | bash "$SCRIPTS/detect-manifest-edit.sh" 2>&1; echo "exit=$?")
assert_contains "$result" "exit=2" "concurrent addition cannot hide another dependency selector change"

# Missing prerequisites must not turn an edit into permission.
mkdir no-python
test_bash=$(command -v bash)
result=$(PATH="$VS_TMPDIR/no-python" "$test_bash" "$SCRIPTS/detect-manifest-edit.sh" <<< '{}' 2>&1; echo "exit=$?")
assert_contains "$result" "exit=2" "missing Python blocks"

finish_test
