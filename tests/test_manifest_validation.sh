#!/usr/bin/env bash
VS_TEST_NAME="manifest-validation"
TESTS_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$TESTS_DIR/.." && pwd)"
source "$TESTS_DIR/assert.sh"
VS_VALIDATE_TMP=$(mktemp -d)
trap 'rm -rf "$VS_VALIDATE_TMP"' EXIT
cd "$VS_VALIDATE_TMP"
check_content() {
  local expected="$1" path="$2" content="$3" label="$4"
  printf '%s' "$content" | bash "$ROOT/scripts/audit-state.sh" validate-content "$path" >/dev/null 2>&1
  assert_exit_code "$expected" "$?" "$label"
}
check_content 0 package.json '{"dependencies":{"lodash":"^4.17.21"}}' 'valid npm range retained'
check_content 2 package.json '{"dependencies": ["lodash"]}' 'npm list does not masquerade as registry map'
check_content 2 package.json '{"dependencies":{"lodash":false}}' 'npm non-string version rejected'
check_content 2 package.json '{"dependencies":{},"dependencies":{"lodash":"4.17.21"}}' 'duplicate npm keys rejected'
check_content 2 package.json '{oops' 'invalid JSON rejected'
check_content 0 pyproject.toml $'[project]\ndependencies=["requests==2.31.0"]\n' 'valid pyproject'
check_content 2 pyproject.toml $'[project]\ndependencies="requests==2.31.0"\n' 'pyproject dependency list schema'
check_content 2 pyproject.toml $'[project]\ndependencies=[false]\n' 'pyproject non-string dependency'
check_content 2 pyproject.toml $'[project]\ndynamic=["dependencies"]\n' 'dynamic dependency discovery cannot fail open'
check_content 0 Cargo.toml $'[dependencies]\nserde={version="1.0.196"}\n' 'valid cargo'
check_content 2 Cargo.toml $'[dependencies]\nserde=false\n' 'cargo unsupported dependency type'
check_content 2 Cargo.toml $'[dependencies\n' 'invalid TOML'
check_content 0 Demo.csproj '<Project><ItemGroup><PackageReference Include="Example" Version="1.0.0" /></ItemGroup></Project>' 'valid XML'
check_content 2 Demo.csproj '<Project><ItemGroup>' 'invalid XML'
check_content 2 Demo.csproj '<NotProject />' 'non-project XML rejected'
check_content 0 requirements.txt $'requests==2.31.0\n-r base.txt\n-e .\n' 'valid requirements syntax'
check_content 2 requirements.txt $'requests ===\n' 'malformed requirements version rejected'
check_content 2 requirements.txt $'this is not a dependency\n' 'unrecognized requirement fails closed'
check_content 2 README.md 'hello' 'unsupported manifest validation rejected'

# Strict extraction must cover dependency declarations old parsers ignored.
printf '%s\n' '[target."cfg(unix)".dependencies]' 'renamed = { package = "real-crate", version = "1.2.3" }' > Cargo.toml
result=$(bash "$ROOT/scripts/audit-state.sh" deps Cargo.toml)
assert_eq $'real-crate\t1.2.3' "$result" 'target cargo dependencies use registry package name'
printf '%s\n' '<Project><ItemGroup><PackageReference Include="Example"><Version>1.2.3</Version></PackageReference></ItemGroup></Project>' > Demo.csproj
result=$(bash "$ROOT/scripts/audit-state.sh" deps Demo.csproj)
assert_eq $'Example\t1.2.3' "$result" 'nested NuGet version extracted'
printf '%s\n' '[dependency-groups]' 'dev = ["pytest==8.0.0"]' > pyproject.toml
result=$(bash "$ROOT/scripts/audit-state.sh" deps pyproject.toml)
assert_eq $'pytest\t8.0.0' "$result" 'PEP 735 dependency groups extracted'
printf '%s\n' 'demo==1!2.0' > requirements.txt
result=$(bash "$ROOT/scripts/audit-state.sh" deps requirements.txt)
assert_eq $'demo\t1!2.0' "$result" 'Python epoch version remains exact'
printf '%s\n' '[project]' 'dependencies = ["demo==1!2.0"]' > pyproject.toml
result=$(bash "$ROOT/scripts/audit-state.sh" deps pyproject.toml)
assert_eq $'demo\t1!2.0' "$result" 'pyproject epoch version remains exact'
fingerprint() {
  printf '%s' "$2" | bash "$ROOT/scripts/audit-state.sh" dependency-fingerprint-content "$1"
}
first=$(fingerprint package.json '{"name":"before","dependencies":{"local":"file:../one","lodash":"^4.17.21"}}')
second=$(fingerprint package.json '{"name":"after","dependencies":{"local":"file:../one","lodash":"^4.17.21"}}')
assert_eq "$first" "$second" 'metadata change leaves dependency fingerprint unchanged'
second=$(fingerprint package.json '{"name":"before","dependencies":{"local":"file:../two","lodash":"^4.17.21"}}')
[[ "$first" != "$second" ]] || _fail 'local dependency change affects fingerprint'
second=$(fingerprint package.json '{"name":"before","dependencies":{"local":"file:../one","lodash":"~4.17.21"}}')
[[ "$first" != "$second" ]] || _fail 'selector change affects fingerprint even with same baseline version'
finish_test
