#!/usr/bin/env bash
VS_TEST_NAME="documentation"
source "$(dirname "$0")/assert.sh"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
skill=$(<"$ROOT/skills/version-sentinel/SKILL.md")
privacy=$(<"$ROOT/PRIVACY.md")

assert_contains "$skill" "warns" "skill describes warning policy"
assert_contains "$skill" "allow the tool call" "skill forbids blocking work"
assert_contains "$skill" "optional" "verification is optional"

assert_contains "$privacy" ".version-sentinel/.etag-cache/" \
  "privacy policy names the registry cache"
assert_contains "$privacy" "ETags and full registry response bodies" \
  "privacy policy describes cached data"
assert_contains "$privacy" "To remove" "privacy policy gives deletion guidance"
assert_contains "$privacy" "delete" "privacy policy names deletion action"

finish_test
