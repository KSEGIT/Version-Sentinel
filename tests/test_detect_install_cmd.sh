#!/usr/bin/env bash
VS_TEST_NAME="detect-install-cmd"
FIXTURES="$(cd "$(dirname "$0")" && pwd)/fixtures"
source "$(dirname "$0")/assert.sh"

VS_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$VS_TMPDIR"' EXIT
SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/scripts/detect-install-cmd.sh"

cd "$VS_TMPDIR"

# Case 1: npm install X@Y with no sidecar → block
result=$(cat "$FIXTURES/bash_npm_install.json" | bash "$SCRIPT" 2>&1; echo "exit=$?")
assert_contains "$result" "BLOCKED" "npm install blocked"
assert_contains "$result" "lodash" "npm install names pkg"

# Case 1b: env -S command strings cannot be parsed safely → fail closed
result=$(echo '{"tool_name":"Bash","tool_input":{"command":"env -S npm install lodash@4.17.21"}}' | bash "$SCRIPT" 2>&1; echo "exit=$?")
assert_contains "$result" "BLOCKED" "env -S install blocked"
assert_contains "$result" "env -S" "env -S install explains ambiguity"
assert_contains "$result" "exit=2" "env -S install: exit 2"

# npm exposes arbitrary config keys as CLI flags. Unknown flags are ambiguous
# because they may consume the next word, so the blocking path fails closed.
result=$(echo '{"tool_name":"Bash","tool_input":{"command":"npm install --future-option value lodash@4.17.21"}}' | bash "$SCRIPT" 2>&1; echo "exit=$?")
assert_contains "$result" "BLOCKED" "unknown npm option blocked"
assert_contains "$result" "npm option --future-option" "unknown npm option explains ambiguity"
assert_contains "$result" "exit=2" "unknown npm option exits 2"

# Case 2: pip install X==Y with no sidecar → block
result=$(cat "$FIXTURES/bash_pip_install.json" | bash "$SCRIPT" 2>&1; echo "exit=$?")
assert_contains "$result" "BLOCKED" "pip install blocked"
assert_contains "$result" "requests" "pip install names pkg"

# Case 3: Unrelated bash command → pass
result=$(echo '{"tool_name":"Bash","tool_input":{"command":"ls -la"}}' | bash "$SCRIPT" 2>&1; echo "exit=$?")
assert_contains "$result" "exit=0" "unrelated cmd: exit 0"

# Case 4: install without version → block with exact retry guidance
result=$(echo '{"tool_name":"Bash","tool_input":{"command":"npm install lodash"}}' | bash "$SCRIPT" 2>&1; echo "exit=$?")
assert_contains "$result" "BLOCKED" "npm no-version install: blocked"
assert_contains "$result" "npm install lodash@<version>" "npm no-version install: exact retry"
assert_contains "$result" "exit=2" "npm no-version install: exit 2"

# Case 4b: registry tags are not exact versions
for tag in latest next; do
  result=$(echo '{"tool_name":"Bash","tool_input":{"command":"npm install lodash@'"$tag"'"}}' | bash "$SCRIPT" 2>&1; echo "exit=$?")
  assert_contains "$result" "BLOCKED" "npm $tag install: blocked"
  assert_contains "$result" "explicit registry version" "npm $tag install: explains requirement"
  assert_contains "$result" "exit=2" "npm $tag install: exit 2"
done

# Case 4c: every recognized package manager fails closed when a registry
# package has no explicit version.
for command in \
  "npm install lodash" \
  "pnpm add lodash" \
  "yarn add lodash" \
  "bun add lodash" \
  "pip install requests" \
  "pip3 install requests" \
  "poetry add requests" \
  "uv add requests" \
  "uv pip install requests" \
  "cargo add serde" \
  "dotnet add package Newtonsoft.Json"; do
  result=$(jq -nc --arg command "$command" '{tool_name:"Bash",tool_input:{command:$command}}' | bash "$SCRIPT" 2>&1; echo "exit=$?")
  assert_contains "$result" "BLOCKED" "bare registry install blocked: $command"
  assert_contains "$result" "exit=2" "bare registry install exits 2: $command"
done

result=$(echo '{"tool_name":"Bash","tool_input":{"command":"pip install requests"}}' | bash "$SCRIPT" 2>&1; echo "exit=$?")
assert_contains "$result" "pip install requests==<version>" "pip no-version install: exact retry"
result=$(echo '{"tool_name":"Bash","tool_input":{"command":"cargo add serde"}}' | bash "$SCRIPT" 2>&1; echo "exit=$?")
assert_contains "$result" "cargo add serde@<version>" "cargo no-version install: exact retry"
result=$(echo '{"tool_name":"Bash","tool_input":{"command":"dotnet add package Newtonsoft.Json"}}' | bash "$SCRIPT" 2>&1; echo "exit=$?")
assert_contains "$result" "dotnet add package Newtonsoft.Json --version <version>" "dotnet no-version install: exact retry"

# Scoped packages and all floating npm selector forms are also unpinned.
for target in "@scope/pkg" "lodash@latest" "lodash@next" "lodash@beta" "lodash@*"; do
  command="npm install $target"
  result=$(jq -nc --arg command "$command" '{tool_name:"Bash",tool_input:{command:$command}}' | bash "$SCRIPT" 2>&1; echo "exit=$?")
  assert_contains "$result" "BLOCKED" "npm floating/scoped target blocked: $target"
  assert_contains "$result" "exit=2" "npm floating/scoped target exits 2: $target"
done

# Ranges, exclusions, wildcards, and compounds all block for every ecosystem.
for command in \
  "npm install lodash@^1.2.3" \
  "npm install lodash@!=1.2.3" \
  "npm install lodash@1.*" \
  'npm install "lodash@>=1.2.3 <2.0.0"' \
  "pip install requests>=2.31.0" \
  "pip install requests!=2.31.0" \
  "pip install requests==2.*" \
  'pip install "requests>=2,<3"' \
  "poetry add flask@^3.0.0" \
  "poetry add flask@!=3.0.0" \
  "poetry add flask@3.*" \
  'poetry add "flask@>=3,<4"' \
  "cargo add serde@1.0.196" \
  "cargo add serde@^1.0.196" \
  "cargo add serde@!=1.0.196" \
  "cargo add serde@1.*" \
  'cargo add "serde@>=1,<2"'; do
  result=$(jq -nc --arg command "$command" '{tool_name:"Bash",tool_input:{command:$command}}' | bash "$SCRIPT" 2>&1; echo "exit=$?")
  assert_contains "$result" "BLOCKED" "non-exact registry selector blocked: $command"
  assert_contains "$result" "exit=2" "non-exact registry selector exits 2: $command"
done

# Shell quotes around one package argument do not bypass either blocking path.
for command in 'npm install "lodash"' "npm install 'lodash@9.9.9'" \
               'pip install "requests"' "pip install 'requests==9.9.9'"; do
  result=$(jq -nc --arg command "$command" '{tool_name:"Bash",tool_input:{command:$command}}' | bash "$SCRIPT" 2>&1; echo "exit=$?")
  assert_contains "$result" "BLOCKED" "quoted registry package blocked: $command"
  assert_contains "$result" "exit=2" "quoted registry package exits 2: $command"
done

for command in 'npm install "./local-package"' \
               "npm install 'https://example.com/pkg.tgz'" \
               'pip install "./local-package"' \
               "pip install 'https://example.com/pkg.whl'"; do
  result=$(jq -nc --arg command "$command" '{tool_name:"Bash",tool_input:{command:$command}}' | bash "$SCRIPT" 2>&1; echo "exit=$?")
  assert_contains "$result" "exit=0" "quoted non-registry target passes: $command"
done

for target in "compat@npm:lodash" "compat@npm:lodash@latest"; do
  command="npm install $target"
  result=$(jq -nc --arg command "$command" '{tool_name:"Bash",tool_input:{command:$command}}' | bash "$SCRIPT" 2>&1; echo "exit=$?")
  assert_contains "$result" "Package: lodash (npm)." "npm alias names real target: $target"
  assert_contains "$result" "exit=2" "npm alias blocks: $target"
done

# Case 4d: install inputs that are not registry package names still pass.
for command in \
  "pip install -r requirements.txt" \
  "pip install -e ." \
  "pip install ./local-package" \
  "pip install https://example.com/pkg.whl" \
  "npm install ./local-package" \
  "npm install local-package.tgz" \
  "npm install link:../local-package" \
  "npm install workspace:*" \
  "npm install git+https://example.com/repo.git" \
  "npm install github:user/repo" \
  "npm install https://example.com/pkg.tgz" \
  "poetry add ../local-package" \
  "poetry add git+https://example.com/repo.git" \
  "poetry add https://example.com/pkg.whl" \
  "cargo add --path ../local-crate" \
  "cargo add --git https://example.com/repo.git"; do
  result=$(jq -nc --arg command "$command" '{tool_name:"Bash",tool_input:{command:$command}}' | bash "$SCRIPT" 2>&1; echo "exit=$?")
  assert_contains "$result" "exit=0" "non-registry install target passes: $command"
done

# Case 5: fresh sidecar → pass
mkdir -p .version-sentinel
now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
cat > .version-sentinel/checks.json <<EOF
{"entries":[
  {"ecosystem":"npm","pkg":"lodash","version":"4.17.21","source":"https://x","checkedAt":"$now"},
  {"ecosystem":"pip","pkg":"requests","version":"2.31.0","source":"https://x","checkedAt":"$now"},
  {"ecosystem":"pip","pkg":"flask","version":"3.0.0","source":"https://x","checkedAt":"$now"},
  {"ecosystem":"cargo","pkg":"serde","version":"1.0.196","source":"https://x","checkedAt":"$now"}
]}
EOF
result=$(cat "$FIXTURES/bash_npm_install.json" | bash "$SCRIPT" 2>&1; echo "exit=$?")
assert_contains "$result" "exit=0" "fresh sidecar: pass"

result=$(echo '{"tool_name":"Bash","tool_input":{"command":"npm install compat@npm:lodash@4.17.21"}}' | bash "$SCRIPT" 2>&1; echo "exit=$?")
assert_contains "$result" "exit=0" "versioned npm alias uses real target sidecar entry"

for command in \
  "npm install lodash@=4.17.21" \
  "pip install requests==2.31.0" \
  "poetry add flask@=3.0.0" \
  "cargo add serde@=1.0.196"; do
  result=$(jq -nc --arg command "$command" '{tool_name:"Bash",tool_input:{command:$command}}' | bash "$SCRIPT" 2>&1; echo "exit=$?")
  assert_contains "$result" "exit=0" "normalized exact selector uses sidecar entry: $command"
done

cd "$OLDPWD"
finish_test
