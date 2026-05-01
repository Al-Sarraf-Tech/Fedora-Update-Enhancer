#!/usr/bin/env bash
# lib/core.sh — primitive helpers (no I/O).
# Sourced by bin/elegant-updater.sh and other libs. Idempotent.

if [[ -n "${__FUE_CORE_LOADED__:-}" ]]; then return 0; fi
__FUE_CORE_LOADED__=1

if (( BASH_VERSINFO[0] < 4 )); then
  printf 'fatal: bash >= 4 required (have %s)\n' "$BASH_VERSION" >&2
  exit 64
fi

clamp_int() {
  local val="$1" lo="$2" hi="$3"
  if (( val < lo )); then echo "$lo"
  elif (( val > hi )); then echo "$hi"
  else echo "$val"; fi
}

as_positive_int() {
  local raw="$1" fallback="$2"
  if [[ "$raw" =~ ^[0-9]+$ ]] && (( raw > 0 )); then echo "$raw"
  else echo "$fallback"; fi
}

calc_jobs_from_load() {
  local cores="$1" loadavg="$2" min_jobs="$3" max_jobs="$4"
  awk -v cores="$cores" -v loadavg="$loadavg" -v min_jobs="$min_jobs" -v max_jobs="$max_jobs" '
    BEGIN {
      if (cores < 1) cores = 1
      if (max_jobs < min_jobs) max_jobs = min_jobs
      if (min_jobs > cores) min_jobs = cores
      if (max_jobs > cores) max_jobs = cores
      if (min_jobs < 1) min_jobs = 1
      if (max_jobs < 1) max_jobs = 1
      ratio = loadavg / cores
      if (ratio < 0) ratio = 0
      if (ratio > 1) ratio = 1
      span = max_jobs - min_jobs
      jobs = int(max_jobs - (ratio * span) + 0.5)
      if (jobs < min_jobs) jobs = min_jobs
      if (jobs > max_jobs) jobs = max_jobs
      print jobs
    }'
}

string_in_array() {
  local needle="$1"; shift
  local item
  for item in "$@"; do
    [[ "$item" == "$needle" ]] && return 0
  done
  return 1
}

require_command() {
  local cmd="$1" hint="${2:-}"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    printf 'fatal: required command not found: %s%s\n' "$cmd" \
      "${hint:+ ($hint)}" >&2
    return 1
  fi
}

generate_run_id() {
  local ts
  ts="$(date -u +%Y%m%dT%H%M%SZ)"
  printf '%s-%05d' "$ts" "$$"
}

iso_now() { date -u +%Y-%m-%dT%H:%M:%SZ; }
epoch_now() { date -u +%s; }
