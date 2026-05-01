#!/usr/bin/env bats
# tests/unit/core.bats — pure helper tests.

load "../helper"

setup() { setup_bats_env; source_lib core; }
teardown() { teardown_bats_env; }

@test "clamp_int: in-range value passes through" {
  result="$(clamp_int 5 1 10)"
  [ "$result" = "5" ]
}

@test "clamp_int: below lo clamps to lo" {
  result="$(clamp_int 0 1 10)"
  [ "$result" = "1" ]
}

@test "clamp_int: above hi clamps to hi" {
  result="$(clamp_int 99 1 10)"
  [ "$result" = "10" ]
}

@test "as_positive_int: valid positive returns input" {
  result="$(as_positive_int 7 99)"
  [ "$result" = "7" ]
}

@test "as_positive_int: negative falls back" {
  result="$(as_positive_int -3 99)"
  [ "$result" = "99" ]
}

@test "as_positive_int: non-numeric falls back" {
  result="$(as_positive_int abc 42)"
  [ "$result" = "42" ]
}

@test "as_positive_int: zero falls back" {
  result="$(as_positive_int 0 17)"
  [ "$result" = "17" ]
}

@test "calc_jobs_from_load: idle system trends to max" {
  result="$(calc_jobs_from_load 16 0.0 4 12)"
  [ "$result" = "12" ]
}

@test "calc_jobs_from_load: fully loaded trends to min" {
  result="$(calc_jobs_from_load 4 4.0 2 8)"
  # cores=4 caps max to 4; ratio=1 → min
  [ "$result" = "2" ]
}

@test "calc_jobs_from_load: zero cores treated as 1" {
  result="$(calc_jobs_from_load 0 0.5 1 4)"
  # min/max clamp to cores=1; result is 1
  [ "$result" = "1" ]
}

@test "string_in_array: needle present" {
  arr=(alpha beta gamma)
  string_in_array beta "${arr[@]}"
}

@test "string_in_array: needle absent" {
  arr=(alpha beta gamma)
  ! string_in_array delta "${arr[@]}"
}

@test "generate_run_id format" {
  rid="$(generate_run_id)"
  [[ "$rid" =~ ^[0-9]{8}T[0-9]{6}Z-[0-9]+$ ]]
}

@test "iso_now is ISO-8601 Z-suffix" {
  ts="$(iso_now)"
  [[ "$ts" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]]
}

@test "epoch_now is integer seconds" {
  ep="$(epoch_now)"
  [[ "$ep" =~ ^[0-9]+$ ]]
  (( ep > 1700000000 ))
}

@test "require_command: present command returns 0" {
  require_command bash
}

@test "require_command: missing command returns 1 + writes to stderr" {
  run require_command __definitely_not_a_command__
  [ "$status" -ne 0 ]
  [[ "$output" =~ "fatal: required command not found" ]]
}
