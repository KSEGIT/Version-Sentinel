#!/usr/bin/env bash
# XML formatting does not change PackageReference meaning; versions/conditions do.
VS_TEST_NAME="xml-dependency-intents"
TESTS_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPTS="$(cd "$TESTS_DIR/../scripts" && pwd)"
source "$TESTS_DIR/assert.sh"
source "$TESTS_DIR/registry-fixture.sh"
VS_TMPDIR=$(mktemp -d)
trap 'rm -rf "$VS_TMPDIR"' EXIT
cd "$VS_TMPDIR" || exit 1
registry_fixture_setup
printf '%s\n' '<Project><ItemGroup><PackageReference Include="Example" Version="13.0.3" Condition="enabled" /></ItemGroup></Project>' > Demo.csproj
bash "$SCRIPTS/check-versions.sh" >/dev/null 2>&1
probe() {
  jq -nc --arg content "$1" '{tool_name:"Write",tool_input:{file_path:"Demo.csproj",content:$content}}' \
    | bash "$SCRIPTS/detect-manifest-edit.sh" 2>&1
}
pretty=$'<Project>\n  <ItemGroup>\n    <PackageReference Condition="enabled" Version="13.0.3" Include="Example">\n    </PackageReference>\n  </ItemGroup>\n</Project>\n'
result=$(probe "$pretty"); status=$?
assert_exit_code 0 "$status" 'attribute order and pretty-printing need no registry recheck'
for changed in \
  '<Project><ItemGroup><PackageReference Include="Example" Version="13.0.1" Condition="enabled" /></ItemGroup></Project>' \
  '<Project><ItemGroup><PackageReference Include="Example" Version="13.0.3" Condition="disabled" /></ItemGroup></Project>' \
  '<Project><ItemGroup><PackageReference Include="Example" Version="13.0.3" Condition="enabled" /><PackageReference Include="Other" Version="13.0.3" /></ItemGroup></Project>'; do
  result=$(probe "$changed"); status=$?
  assert_exit_code 2 "$status" 'version, condition, and added references still require online records'
done
printf '%s\n' '<Project><ItemGroup><PackageReference Include="Example"><Version>13.0.3</Version><PrivateAssets>all</PrivateAssets></PackageReference></ItemGroup></Project>' > Demo.csproj
bash "$SCRIPTS/check-versions.sh" >/dev/null 2>&1
pretty=$'<Project>\n  <ItemGroup>\n    <PackageReference Include="Example">\n      <Version>13.0.3</Version>\n      <PrivateAssets>all</PrivateAssets>\n    </PackageReference>\n  </ItemGroup>\n</Project>\n'
result=$(probe "$pretty"); status=$?
assert_exit_code 0 "$status" 'child-element indentation and tails do not alter dependency intent'
changed='<Project><ItemGroup><PackageReference Include="Example"><Version>13.0.1</Version><PrivateAssets>all</PrivateAssets></PackageReference></ItemGroup></Project>'
result=$(probe "$changed"); status=$?
assert_exit_code 2 "$status" 'meaningful child Version change stays gated'
finish_test
