#!/usr/bin/env bats
# tests/integration/cli.bats — exercise the orchestrator CLI surface.

load "../helper"

setup() {
  setup_bats_env
  ELEGANT="${PROJECT_ROOT}/bin/elegant-updater.sh"
}
teardown() { teardown_bats_env; }

@test "--version prints version" {
  run "$ELEGANT" --version
  [ "$status" -eq 0 ]
  [[ "$output" =~ ^elegant-updater\ [0-9]+\.[0-9]+\.[0-9]+$ ]]
}

@test "--help prints usage and exits 0" {
  run "$ELEGANT" --help
  [ "$status" -eq 0 ]
  [[ "$output" =~ "Usage:" ]]
  [[ "$output" =~ "--dry-run" ]]
  [[ "$output" =~ "--json" ]]
}

@test "unknown flag exits 64" {
  run "$ELEGANT" --not-a-real-flag
  [ "$status" -eq 64 ]
  [[ "$output" =~ "unknown flag" ]]
}

@test "non-root invocation refuses cleanly" {
  if [ "$EUID" -eq 0 ]; then
    skip "running as root"
  fi
  run env FUE_LOG_FILE_ENABLED=0 FUE_LOG_JOURNALD=0 "$ELEGANT" --no-banner
  [ "$status" -ne 0 ]
  [[ "$output" =~ "Run as root" ]] || [[ "$output" =~ "Pre-flight failed" ]]
}

@test "syntax: bash -n succeeds on orchestrator" {
  run bash -n "$ELEGANT"
  [ "$status" -eq 0 ]
}

@test "syntax: bash -n succeeds on every lib" {
  for f in "${PROJECT_ROOT}/lib"/*.sh; do
    run bash -n "$f"
    [ "$status" -eq 0 ]
  done
}
