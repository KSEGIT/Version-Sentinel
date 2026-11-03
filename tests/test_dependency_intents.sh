#!/usr/bin/env bash
# Raw selectors must survive normalization so simultaneous additions cannot mask changes.
VS_TEST_NAME="dependency-intents"
TESTS_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPTS="$(cd "$TESTS_DIR/../scripts" && pwd)"
source "$TESTS_DIR/assert.sh"
intents() {
  printf '%s' "$2" | bash "$SCRIPTS/audit-state.sh" deps-intents-content "$1"
}
pre=$(intents package.json '{"dependencies":{"lodash":"^4.17.21"}}')
post=$(intents package.json '{"dependencies":{"lodash":"~4.17.21","other":"1.0.0"}}')
changed=$(python3 - "$pre" "$post" <<'PY'
import json,sys
before={(e['pkg'],e['version'],e['intent']) for e in json.loads(sys.argv[1] or '[]')}
after=json.loads(sys.argv[2] or '[]')
print(','.join(sorted(e['pkg'] for e in after if (e['pkg'],e['version'],e['intent']) not in before)))
PY
)
assert_eq 'lodash,other' "$changed" 'selector change survives concurrent unrelated addition'

pre=$(intents package.json '{"name":"before","dependencies":{"compat":"npm:lodash@^4.17.21"}}')
post=$(intents package.json '{"name":"after","dependencies":{"compat":"npm:lodash@^4.17.21"}}')
assert_eq "$pre" "$post" 'metadata does not alter registry intent'
assert_eq 'lodash' "$(printf '%s' "$pre" | jq -r '.[0].pkg')" 'npm alias emits real package name'
assert_eq '4.17.21' "$(printf '%s' "$pre" | jq -r '.[0].version')" 'npm intent retains exact checked bound'
post=$(intents package.json '{"dependencies":{"compat":"npm:lodash@~4.17.21"}}')
[[ "$pre" != "$post" ]] || _fail 'npm alias selector intent must change'
post=$(intents package.json '{"devDependencies":{"compat":"npm:lodash@^4.17.21"}}')
[[ "$pre" != "$post" ]] || _fail 'dependency group move must change registry intent'

for path in requirements.txt pyproject.toml Cargo.toml Demo.csproj; do
  case "$path" in
    requirements.txt) before='requests>=2.31.0'; after='requests==2.31.0' ;;
    pyproject.toml) before=$'[project]\ndependencies=["requests>=2.31.0"]'; after=$'[project]\ndependencies=["requests==2.31.0"]' ;;
    Cargo.toml) before=$'[dependencies]\nserde="^1.0.196"'; after=$'[dependencies]\nserde="=1.0.196"' ;;
    Demo.csproj) before='<Project><ItemGroup><PackageReference Include="Example" Version="1.0.0" /></ItemGroup></Project>'; after='<Project><ItemGroup><PackageReference Include="Example" Version="=1.0.0" /></ItemGroup></Project>' ;;
  esac
  pre=$(intents "$path" "$before")
  post=$(intents "$path" "$after")
  [[ -n "$pre" && -n "$post" && "$pre" != "$post" ]] || _fail "$path raw selector change must remain visible"
done
pre=$(intents pyproject.toml $'[project]\ndependencies=["requests==2.31.0"]')
post=$(intents pyproject.toml $'[build-system]\nrequires=["requests==2.31.0"]')
[[ -n "$pre" && -n "$post" && "$pre" != "$post" ]] || _fail 'build/project requirement locations must remain distinct'
finish_test
