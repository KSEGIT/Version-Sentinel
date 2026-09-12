#!/usr/bin/env bash
VS_TEST_NAME="documentation"
source "$(dirname "$0")/assert.sh"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
skill=$(<"$ROOT/skills/version-sentinel/SKILL.md")
privacy=$(<"$ROOT/PRIVACY.md")

assert_contains "$skill" "public package without a version" \
  "public package without version is handled"
assert_contains "$skill" "latest-version request" \
  "public package without version uses latest"
assert_contains "$skill" "Ask the user only when the dependency is" \
  "clarification guidance is explicit"
assert_contains "$skill" "ambiguous or private" \
  "clarification is limited to ambiguous or private dependencies"

assert_contains "$privacy" ".version-sentinel/.etag-cache/" \
  "privacy policy names the registry cache"
assert_contains "$privacy" "ETags and full registry response bodies" \
  "privacy policy describes cached data"
assert_contains "$privacy" "To remove" "privacy policy gives deletion guidance"
assert_contains "$privacy" "delete" "privacy policy names deletion action"

finish_test
