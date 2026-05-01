#!/usr/bin/env bats
# tests/integration/golden.bats — output stability tests.

load "../helper"

setup() {
  setup_bats_env
  ELEGANT="${PROJECT_ROOT}/bin/elegant-updater.sh"
}
teardown() { teardown_bats_env; }

@test "golden: --help output matches expected" {
  run "$ELEGANT" --help
  [ "$status" -eq 0 ]
  expected="$(cat "${PROJECT_ROOT}/tests/golden/help.txt")"
  [ "$output" = "$expected" ]
}

@test "golden: --version output is semver-formatted" {
  run "$ELEGANT" --version
  [ "$status" -eq 0 ]
  [[ "$output" =~ ^elegant-updater\ [0-9]+\.[0-9]+\.[0-9]+(-[a-z0-9.-]+)?$ ]]
}
