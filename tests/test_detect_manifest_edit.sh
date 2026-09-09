#!/usr/bin/env bash
VS_TEST_NAME="detect-manifest-edit"
TESTS_DIR="$(cd "$(dirname "$0")" && pwd)"
FIXTURES="$TESTS_DIR/fixtures"
source "$TESTS_DIR/assert.sh"

VS_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$VS_TMPDIR"' EXIT

SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/scripts/detect-manifest-edit.sh"

cd "$VS_TMPDIR"
cat > package.json <<EOF
{
  "name": "fixture",
  "version": "1.0.0",
  "dependencies": {
    "express": "4.19.2"
  }
}
EOF

substitute() {
  sed "s|{{CWD}}|$VS_TMPDIR|g" "$1"
}

hook_write() {
  local path="$1" content="$2"
  jq -nc --arg path "$path" --arg content "$content" \
    '{tool_name:"Write",tool_input:{file_path:$path,content:$content}}' \
    | bash "$SCRIPT" 2>&1
}

# Case 1: Edit adds lodash → block
input=$(substitute "$FIXTURES/edit_input_add_lodash.json")
result=$(echo "$input" | bash "$SCRIPT" 2>&1; echo "exit=$?")
assert_contains "$result" "BLOCKED" "edit-add: blocked"
assert_contains "$result" "lodash" "edit-add: names pkg"
assert_contains "$result" "exit=2" "edit-add: exit 2"

# Case 2: Write new content w/ lodash → block
input=$(substitute "$FIXTURES/write_input_new_package.json")
result=$(echo "$input" | bash "$SCRIPT" 2>&1; echo "exit=$?")
assert_contains "$result" "BLOCKED" "write: blocked"
assert_contains "$result" "lodash" "write: names pkg"

# Case 3: MultiEdit bumps express → block
input=$(substitute "$FIXTURES/multiedit_input_bump.json")
result=$(echo "$input" | bash "$SCRIPT" 2>&1; echo "exit=$?")
assert_contains "$result" "BLOCKED" "multiedit-bump: blocked"
assert_contains "$result" "express" "multiedit-bump: names pkg"

# Case 3b: Edit adds lodash but fresh sidecar exists → allowed
now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
mkdir -p .version-sentinel
printf '{"entries":[{"ecosystem":"npm","pkg":"lodash","version":"4.17.21","source":"https://npmjs.com","checkedAt":"%s"}]}' "$now" \
  > .version-sentinel/checks.json
input=$(substitute "$FIXTURES/edit_input_add_lodash.json")
result=$(echo "$input" | bash "$SCRIPT" 2>&1; echo "exit=$?")
assert_contains "$result" "exit=0" "edit-add with fresh sidecar: exit 0"

alias_content='{"dependencies":{"compat":"npm:lodash@4.17.21"}}'
result=$(hook_write "$VS_TMPDIR/alias-fresh/package.json" "$alias_content"; echo "exit=$?")
assert_contains "$result" "exit=0" "versioned npm manifest alias uses real target sidecar entry"
rm -rf .version-sentinel

# Case 4: Edit on a non-manifest file → pass silently
cat > README.md <<EOF
# Demo
EOF
input='{"tool_name":"Edit","tool_input":{"file_path":"'"$VS_TMPDIR"'/README.md","old_string":"# Demo","new_string":"# Demo2","replace_all":false}}'
result=$(echo "$input" | bash "$SCRIPT" 2>&1; echo "exit=$?")
assert_contains "$result" "exit=0" "non-manifest: exit 0"

# Case 4b: Kimi-style Edit payload (tool_input.path instead of file_path) → block
input=$(substitute "$FIXTURES/edit_input_kimi_path.json")
result=$(echo "$input" | bash "$SCRIPT" 2>&1; echo "exit=$?")
assert_contains "$result" "BLOCKED" "kimi-path: blocked"
assert_contains "$result" "lodash" "kimi-path: names pkg"
assert_contains "$result" "exit=2" "kimi-path: exit 2"

# Case 5: VS_DISABLE bypass
input=$(substitute "$FIXTURES/edit_input_add_lodash.json")
result=$(echo "$input" | VS_DISABLE=1 bash "$SCRIPT" 2>&1; echo "exit=$?")
assert_contains "$result" "exit=0" "VS_DISABLE: exit 0"

# Unpinned registry entries fail closed through the manifest hook for every
# supported manifest ecosystem.
npm_unpinned='{"dependencies":{"tagged":"latest","next-tag":"next","wild":"*","empty":"","local":"file:../local","shared":"workspace:*"}}'
result=$(hook_write "$VS_TMPDIR/unpinned/package.json" "$npm_unpinned"; echo "exit=$?")
assert_contains "$result" "Package: tagged (npm)." "npm manifest tag: names package"
assert_contains "$result" "explicit registry version" "npm manifest tag: explains requirement"
assert_contains "$result" "exit=2" "npm manifest tag: exit 2"

pip_unpinned=$'requests\n-r base.txt\n-e .\n./local\n'
result=$(hook_write "$VS_TMPDIR/unpinned/requirements.txt" "$pip_unpinned"; echo "exit=$?")
assert_contains "$result" "Package: requests (pip)." "requirements manifest: names package"
assert_contains "$result" "exit=2" "requirements manifest: exit 2"

pyproject_unpinned=$'[project]\ndependencies = ["requests", "local @ file:///tmp/local"]\n[tool.poetry.dependencies]\nflask = "*"\nlocal = { path = "../local" }\n'
result=$(hook_write "$VS_TMPDIR/unpinned/pyproject.toml" "$pyproject_unpinned"; echo "exit=$?")
assert_contains "$result" "Package: requests (pyproject)." "pyproject PEP 621: names package"
assert_contains "$result" "Package: flask (pyproject)." "pyproject Poetry: names package"
assert_contains "$result" "exit=2" "pyproject manifest: exit 2"

cargo_unpinned=$'[package]\nname = "demo"\nversion = "0.1.0"\n[dependencies]\nregistry-dep = {}\nlocal = { path = "../local" }\nshared = { workspace = true }\n'
result=$(hook_write "$VS_TMPDIR/unpinned/Cargo.toml" "$cargo_unpinned"; echo "exit=$?")
assert_contains "$result" "Package: registry-dep (cargo)." "cargo manifest: names package"
assert_contains "$result" "exit=2" "cargo manifest: exit 2"

csproj_unpinned='<Project><ItemGroup><PackageReference Include="Polly" Version="*" /><PackageReference Include="Central.Versioned" /><ProjectReference Include="../Shared/Shared.csproj" /></ItemGroup></Project>'
result=$(hook_write "$VS_TMPDIR/unpinned/Demo.csproj" "$csproj_unpinned"; echo "exit=$?")
assert_contains "$result" "Package: Polly (csproj)." "csproj manifest: names package"
assert_contains "$result" "exit=2" "csproj manifest: exit 2"

# A manifest edit that adds only non-registry sources stays outside the gate.
sources_only='{"dependencies":{"local":"file:../local","git":"git+https://example.com/repo.git","shared":"workspace:*"}}'
result=$(hook_write "$VS_TMPDIR/sources/package.json" "$sources_only"; echo "exit=$?")
assert_contains "$result" "exit=0" "npm non-registry manifest sources pass"

# A fixed devDependency with the same name must not hide a new wildcard in a
# different npm dependency section.
mkdir -p "$VS_TMPDIR/duplicates"
cat > "$VS_TMPDIR/duplicates/package.json" <<'EOF'
{"devDependencies":{"lodash":"4.17.21"}}
EOF
duplicate_post='{"dependencies":{"lodash":"*"},"devDependencies":{"lodash":"4.17.21"}}'
result=$(hook_write "$VS_TMPDIR/duplicates/package.json" "$duplicate_post"; echo "exit=$?")
assert_contains "$result" "Package: lodash (npm)." "npm duplicate section wildcard: names package"
assert_contains "$result" "exit=2" "npm duplicate section wildcard: exit 2"

alias_post='{"dependencies":{"compat":"npm:lodash"}}'
result=$(hook_write "$VS_TMPDIR/aliases/package.json" "$alias_post"; echo "exit=$?")
assert_contains "$result" "Package: lodash (npm)." "npm manifest alias: names real target"
assert_contains "$result" "exit=2" "npm manifest alias: exit 2"

cd "$OLDPWD"
finish_test
