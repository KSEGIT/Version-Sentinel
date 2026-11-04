#!/usr/bin/env bash
# Test-only upstream HTTP fixture. Consumers must provide VS_TMPDIR.
registry_fixture_setup() {
  mkdir -p "$VS_TMPDIR/registry-bin"
  cat > "$VS_TMPDIR/registry-bin/curl" <<'CURL'
#!/usr/bin/env bash
[[ "${VS_FIXTURE_NETWORK_FAIL:-0}" == 1 ]] && exit 7
if [[ -n "${VS_FIXTURE_RESPONSE_FILE:-}" ]]; then
  cat "$VS_FIXTURE_RESPONSE_FILE"
  exit $?
fi
url="${@: -1}"
case "$url" in
  https://registry.npmjs.org/*)
    printf '%s\n' '{"dist-tags":{"latest":"4.17.21"},"versions":{"4.17.21":{},"4.17.20":{},"1.0.0":{},"5.0.0":{}}}' ;;
  https://pypi.org/pypi/flask/json)
    printf '%s\n' '{"info":{"version":"3.0.0"},"releases":{"3.0.0":[{"yanked":false}],"2.0.0":[{"yanked":false}]}}' ;;
  https://pypi.org/pypi/*/json)
    printf '%s\n' '{"info":{"version":"2.31.0"},"releases":{"2.31.0":[{"yanked":false}],"2.30.0":[{"yanked":false}]}}' ;;
  https://api.nuget.org/v3-flatcontainer/*/index.json)
    printf '%s\n' '{"versions":["12.0.0","13.0.1","13.0.3"]}' ;;
  https://crates.io/api/v1/crates/*)
    printf '%s\n' '{"crate":{"max_stable_version":"1.0.196"},"versions":[{"num":"1.0.196","yanked":false},{"num":"1.0.195","yanked":false}]}' ;;
  *) echo "Unexpected upstream URL: $url" >&2; exit 1 ;;
esac
CURL
  chmod +x "$VS_TMPDIR/registry-bin/curl"
  export PATH="$VS_TMPDIR/registry-bin:$PATH" VS_ETAG_DISABLE=1 VS_REGISTRY_RETRIES=1
}
