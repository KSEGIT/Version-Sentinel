#!/usr/bin/env bash
VS_TEST_NAME="registries-offline"
FIXTURES="$(cd "$(dirname "$0")" && pwd)/fixtures"
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "$(dirname "$0")/assert.sh"

# Stub curl: reads URL arg, returns matching fixture
STUB_DIR=$(mktemp -d)
trap 'rm -rf "$STUB_DIR"' EXIT

cat > "$STUB_DIR/curl" <<CURL
#!/usr/bin/env bash
url="\${@: -1}"
case "\$url" in
  *registry.npmjs.org/lodash*)       cat "$FIXTURES/registry_npm_lodash.json" ;;
  *pypi.org/pypi/requests*)          cat "$FIXTURES/registry_pypi_requests.json" ;;
  *nuget.org*newtonsoft.json*)       cat "$FIXTURES/registry_nuget_newtonsoft.json" ;;
  *crates.io/api/v1/crates/serde*)   cat "$FIXTURES/registry_crates_serde.json" ;;
  *)                                 echo "stub: unknown URL \$url" >&2; exit 1 ;;
esac
CURL
chmod +x "$STUB_DIR/curl"
export PATH="$STUB_DIR:$PATH"

source "$SCRIPT_DIR/scripts/lib/registries.sh"

assert_eq "4.17.21"  "$(registry_latest npm lodash)"        "npm latest"
assert_eq "2.31.0"   "$(registry_latest pip requests)"      "pypi latest"
assert_eq "13.0.3"   "$(registry_latest csproj Newtonsoft.Json)" "nuget latest"
assert_eq "1.0.196"  "$(registry_latest cargo serde)"       "crates latest"

finish_test
