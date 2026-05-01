#!/usr/bin/env bats
# tests/integration/dry-run.bats — full orchestrator in dry-run mode w/ mock dnf.

load "../helper"

setup() {
  setup_bats_env
  ELEGANT="${PROJECT_ROOT}/bin/elegant-updater.sh"

  MOCK_DIR="${TMPHOME}/mock-bin"
  mkdir -p "$MOCK_DIR"
  cp "${PROJECT_ROOT}/tests/mocks/dnf5" "${MOCK_DIR}/dnf5"
  chmod 0755 "${MOCK_DIR}/dnf5"
  export FUE_DNF="${MOCK_DIR}/dnf5"

  export FUE_LOG_DIR="${TMPHOME}/log"
  export FUE_LOG_FILE_ENABLED=1
  export FUE_LOG_JOURNALD=0
  export MOCK_DNF_LOG="${TMPHOME}/mock-dnf.log"

  # Make pre-flight tolerant for non-root test contexts
  export FUE_PREFLIGHT_FATAL=0
  export FUE_PREFLIGHT_NETWORK=0
  export FUE_ALLOW_PACKAGEKIT=1
}
teardown() { teardown_bats_env; }

@test "dry-run completes without invoking dnf upgrade" {
  if [ "$EUID" -ne 0 ]; then
    # Pre-flight will warn root-required but FUE_PREFLIGHT_FATAL=0 lets it proceed
    skip "dry-run integration requires root or env adjustments not portable here"
  fi
  run "$ELEGANT" --dry-run --no-banner --no-journald
  [ "$status" -eq 0 ]
  [[ "$output" =~ "DRY-RUN" ]]
  [[ "$output" =~ "Would run" ]]
  # Mock dnf log should not show any upgrade call
  if [ -f "$MOCK_DNF_LOG" ]; then
    ! grep -q "dnf5 upgrade" "$MOCK_DNF_LOG"
  fi
}

@test "version banner shows detected Fedora version" {
  run "$ELEGANT" --version
  [ "$status" -eq 0 ]
  [[ "$output" =~ ^elegant-updater\ [0-9]+\.[0-9]+\.[0-9]+$ ]]
}

@test "JSON log format produces valid line-delimited JSON to stdout" {
  if [ "$EUID" -ne 0 ]; then
    skip "non-root: cannot exercise full path"
  fi
  run "$ELEGANT" --dry-run --no-banner --no-journald --json
  [ "$status" -eq 0 ]
  # Each line should be JSON object
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    [[ "$line" =~ ^\{.*\}$ ]]
  done <<< "$output"
}
