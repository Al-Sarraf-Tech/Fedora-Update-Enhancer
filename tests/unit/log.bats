#!/usr/bin/env bats
# tests/unit/log.bats — log + telemetry behavior.

load "../helper"

setup() {
  setup_bats_env
  export FUE_LOG_DIR="${TMPHOME}/log"
  export FUE_LOG_FILE_ENABLED=1
  export FUE_LOG_JOURNALD=0
  export FUE_RUN_ID="testrun-001"
  export FUE_LOG_FILE="${FUE_LOG_DIR}/run-${FUE_RUN_ID}.log"
  export FUE_TELEMETRY_FILE="${FUE_LOG_DIR}/run-${FUE_RUN_ID}.json"
  source_lib core
  source_lib log
}
teardown() { teardown_bats_env; }

@test "info-level message logs to file in text format" {
  log_info "hello world"
  [ -f "$FUE_LOG_FILE" ]
  grep -q "hello world" "$FUE_LOG_FILE"
}

@test "debug suppressed at default level" {
  log_debug "should not appear"
  [ ! -s "$FUE_LOG_FILE" ] || ! grep -q "should not appear" "$FUE_LOG_FILE"
}

@test "json format produces parseable JSON object" {
  export FUE_LOG_FORMAT=json
  source_lib core
  source_lib log
  out="$(log_info "json msg" 2>&1)"
  [[ "$out" =~ \"level\":\"info\" ]]
  [[ "$out" =~ \"msg\":\"json\ msg\" ]]
  [[ "$out" =~ \"run_id\":\"testrun-001\" ]]
}

@test "json escapes embedded quote and backslash" {
  export FUE_LOG_FORMAT=json
  source_lib core
  source_lib log
  out="$(log_info 'has "quote" and \backslash' 2>&1)"
  [[ "$out" =~ \\\"quote\\\" ]]
  [[ "$out" =~ \\\\backslash ]]
}

@test "telemetry_set + telemetry_flush writes JSON" {
  telemetry_set repos_failed 3
  telemetry_set kernel_updated true
  telemetry_flush
  [ -f "$FUE_TELEMETRY_FILE" ]
  grep -q '"repos_failed":"3"' "$FUE_TELEMETRY_FILE"
  grep -q '"kernel_updated":"true"' "$FUE_TELEMETRY_FILE"
}

@test "telemetry_inc accumulates" {
  telemetry_inc errors 1
  telemetry_inc errors 2
  telemetry_flush
  grep -q '"errors":"3"' "$FUE_TELEMETRY_FILE"
}
