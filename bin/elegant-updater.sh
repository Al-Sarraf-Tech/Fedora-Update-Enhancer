#!/usr/bin/env bash
# elegant-updater.sh — High-performance unattended Fedora updater.
# Modular S+ tier rewrite. See docs/adr/ for design decisions.
#
# Usage: sudo elegant-updater.sh [flags]
#        sudo update                     (when installed as /usr/local/bin/update)
#
# Flags:
#   --version          Print version and exit
#   --help             Print usage and exit
#   --dry-run          Show what would be done; do not modify the system
#   --json             Emit logs as line-delimited JSON
#   --debug            Set log level to debug
#   --quiet            Set log level to warn
#   --no-banner        Suppress the header banner
#   --no-journald      Disable journald logging
#   --audit            Run the S+ audit and exit
#   --uninstall        Remove /usr/local/bin/update and exit
#
# All flags are also settable via environment variables (see docs/CONFIGURATION.md).

set -Eeuo pipefail
IFS=$'\n\t'

readonly FUE_VERSION="2.0.0"

# ---------- Project root resolution ----------
__fue_resolve_self() {
  local src="${BASH_SOURCE[0]}"
  while [[ -L "$src" ]]; do
    local dir
    dir="$(cd -P "$(dirname "$src")" && pwd)"
    src="$(readlink "$src")"
    [[ "$src" != /* ]] && src="${dir}/${src}"
  done
  printf '%s' "$src"
}
__FUE_SELF="$(__fue_resolve_self)"
__FUE_BIN_DIR="$(cd -P "$(dirname "$__FUE_SELF")" && pwd)"
FUE_PROJECT_ROOT="${FUE_PROJECT_ROOT:-$(cd -P "${__FUE_BIN_DIR}/.." && pwd)}"
FUE_LIB_DIR="${FUE_LIB_DIR:-${FUE_PROJECT_ROOT}/lib}"
export FUE_PROJECT_ROOT FUE_LIB_DIR FUE_VERSION

# ---------- Argument parsing (before sourcing log so --json takes effect) ----------
DRY_RUN=0
NO_BANNER=0
SHOW_VERSION=0
SHOW_HELP=0
RUN_AUDIT=0
RUN_UNINSTALL=0

print_help() {
  sed -n '2,21p' "$__FUE_SELF" | sed 's/^# \{0,1\}//'
}

print_version() {
  printf 'elegant-updater %s\n' "$FUE_VERSION"
}

while (( $# > 0 )); do
  case "$1" in
    --version)     SHOW_VERSION=1 ;;
    --help|-h)     SHOW_HELP=1 ;;
    --dry-run)     DRY_RUN=1 ;;
    --json)        FUE_LOG_FORMAT=json ;;
    --debug)       FUE_LOG_LEVEL=debug ;;
    --quiet)       FUE_LOG_LEVEL=warn ;;
    --no-banner)   NO_BANNER=1 ;;
    --no-journald) FUE_LOG_JOURNALD=0 ;;
    --audit)       RUN_AUDIT=1 ;;
    --uninstall)   RUN_UNINSTALL=1 ;;
    --)            shift; break ;;
    *)
      printf 'unknown flag: %s\n' "$1" >&2
      print_help >&2
      exit 64
      ;;
  esac
  shift
done

if (( SHOW_HELP )); then print_help; exit 0; fi
if (( SHOW_VERSION )); then print_version; exit 0; fi

if (( RUN_AUDIT )); then
  exec "${FUE_PROJECT_ROOT}/scripts/s-tier-audit.sh"
fi

if (( RUN_UNINSTALL )); then
  exec "${FUE_PROJECT_ROOT}/scripts/uninstall.sh"
fi

# ---------- Source libraries ----------
# shellcheck source=lib/core.sh
source "${FUE_LIB_DIR}/core.sh"
# shellcheck source=lib/log.sh
source "${FUE_LIB_DIR}/log.sh"
# shellcheck source=lib/system.sh
source "${FUE_LIB_DIR}/system.sh"
# shellcheck source=lib/lock.sh
source "${FUE_LIB_DIR}/lock.sh"
# shellcheck source=lib/preflight.sh
source "${FUE_LIB_DIR}/preflight.sh"
# shellcheck source=lib/postflight.sh
source "${FUE_LIB_DIR}/postflight.sh"
# shellcheck source=lib/dnf.sh
source "${FUE_LIB_DIR}/dnf.sh"
# shellcheck source=lib/repo.sh
source "${FUE_LIB_DIR}/repo.sh"

export FUE_DRY_RUN="$DRY_RUN"

# ---------- Cleanup trap ----------
__fue_at_exit() {
  local rc=$?
  cleanup_repo_backups
  release_lock
  telemetry_set exit_code "$rc"
  telemetry_set finished_at "$(iso_now)"
  telemetry_flush
  return "$rc"
}
trap __fue_at_exit EXIT
trap 'log_error "Interrupted (signal)"; exit 130' INT TERM

# ---------- Validate Fedora version ----------
case "$(validate_fedora_supported; echo $?)" in
  0) : ;;
  1) log_warn "Fedora $(detect_fedora_version) — older than primary target; proceeding" ;;
  2) log_error "Unsupported OS: $(detect_fedora_pretty)"; exit 70 ;;
esac

# ---------- Sizing ----------
CPU_CORES="$(as_positive_int "$(detect_cpu_cores)" 4)"
LOAD1="$(detect_loadavg_1m)"
MIN_CPU_WORKERS="$(as_positive_int "${MIN_CPU_WORKERS:-10}" 10)"
MAX_CPU_WORKERS="$(as_positive_int "${MAX_CPU_WORKERS:-20}" 20)"

if (( CPU_CORES < MIN_CPU_WORKERS )); then
  EFFECTIVE_MIN_CPU_WORKERS="$CPU_CORES"
else
  EFFECTIVE_MIN_CPU_WORKERS="$MIN_CPU_WORKERS"
fi
if (( CPU_CORES < MAX_CPU_WORKERS )); then
  EFFECTIVE_MAX_CPU_WORKERS="$CPU_CORES"
else
  EFFECTIVE_MAX_CPU_WORKERS="$MAX_CPU_WORKERS"
fi
CPU_WORKER_LIMIT_NOTE=""
if (( CPU_CORES < MIN_CPU_WORKERS )); then
  CPU_WORKER_LIMIT_NOTE="Host has fewer than ${MIN_CPU_WORKERS} cores; using ${CPU_CORES} workers max."
fi

ADAPTIVE_JOBS="$(calc_jobs_from_load "$CPU_CORES" "$LOAD1" "$EFFECTIVE_MIN_CPU_WORKERS" "$EFFECTIVE_MAX_CPU_WORKERS")"
JOBS=${JOBS:-$ADAPTIVE_JOBS}
JOBS="$(clamp_int "$JOBS" "$EFFECTIVE_MIN_CPU_WORKERS" "$EFFECTIVE_MAX_CPU_WORKERS")"

DNF_PARALLEL_CAP="$(as_positive_int "${DNF_PARALLEL_CAP:-20}" 20)"
STREAM_MBIT_PER_CONN="$(as_positive_int "${STREAM_MBIT_PER_CONN:-35}" 35)"
STREAM_UTILIZATION_PERCENT="$(as_positive_int "${STREAM_UTILIZATION_PERCENT:-95}" 95)"
(( DNF_PARALLEL_CAP > 20 )) && DNF_PARALLEL_CAP=20
(( STREAM_UTILIZATION_PERCENT > 95 )) && STREAM_UTILIZATION_PERCENT=95

LINK_SPEED_MBPS="$(detect_fastest_link_speed_mbps)"
if [[ "$LINK_SPEED_MBPS" =~ ^[0-9]+$ ]] && (( LINK_SPEED_MBPS > 0 )); then
  LINK_SPEED_MBPS_DISPLAY="$LINK_SPEED_MBPS"
else
  LINK_SPEED_MBPS_DISPLAY="unknown"
fi

CPU_STREAM_LIMIT=$(( JOBS * 2 ))
THEORETICAL_PARALLEL_CAP="$DNF_PARALLEL_CAP"
(( CPU_STREAM_LIMIT < THEORETICAL_PARALLEL_CAP )) && THEORETICAL_PARALLEL_CAP="$CPU_STREAM_LIMIT"

if [[ "$LINK_SPEED_MBPS" =~ ^[0-9]+$ ]] && (( LINK_SPEED_MBPS > 0 )) && (( STREAM_MBIT_PER_CONN > 0 )); then
  LINK_STREAM_LIMIT=$(( LINK_SPEED_MBPS / STREAM_MBIT_PER_CONN ))
  if (( LINK_STREAM_LIMIT > 0 )) && (( LINK_STREAM_LIMIT < THEORETICAL_PARALLEL_CAP )); then
    THEORETICAL_PARALLEL_CAP="$LINK_STREAM_LIMIT"
  fi
fi
(( THEORETICAL_PARALLEL_CAP < 1 )) && THEORETICAL_PARALLEL_CAP=1

ADAPTIVE_MAX_PARALLEL_DOWNLOADS=$(( THEORETICAL_PARALLEL_CAP * STREAM_UTILIZATION_PERCENT / 100 ))
(( ADAPTIVE_MAX_PARALLEL_DOWNLOADS < 1 )) && ADAPTIVE_MAX_PARALLEL_DOWNLOADS=1
MAX_PARALLEL_DOWNLOADS=${MAX_PARALLEL_DOWNLOADS:-$ADAPTIVE_MAX_PARALLEL_DOWNLOADS}
MAX_PARALLEL_DOWNLOADS="$(clamp_int "$MAX_PARALLEL_DOWNLOADS" 1 "$DNF_PARALLEL_CAP")"

# DNF policy knobs
INSTALLONLY_LIMIT="${INSTALLONLY_LIMIT:-3}"
FASTESTMIRROR="${FASTESTMIRROR:-1}"
SKIP_IF_UNAVAILABLE="${SKIP_IF_UNAVAILABLE:-1}"
RETRIES="${RETRIES:-6}"
TIMEOUT="${TIMEOUT:-15}"
MINRATE="${MINRATE:-100k}"
PREFER_MIRRORS="${PREFER_MIRRORS:-1}"
RUN_UPDATE_SWEEP="${RUN_UPDATE_SWEEP:-0}"

if [[ "$SKIP_IF_UNAVAILABLE" == "1" ]]; then
  SKIP_IF_UNAVAILABLE_BOOL=True
else
  SKIP_IF_UNAVAILABLE_BOOL=False
fi

# ---------- Banner ----------
banner() {
  (( NO_BANNER == 1 )) && return 0
  [[ "$FUE_LOG_FORMAT" == "json" ]] && return 0
  printf '\r\n%s\n\n' "${C_BOLD}${C_NEON}╔════════════════════════════════════════════════════════╗${C_RESET}"
  printf '%s\n' "${C_PINK}  ⛭  ✦  ✧  $(build_banner_subtitle) — Snake  ✦  ✧  ⛭${C_RESET}"
  printf '%s\n' "${C_NEON}╚════════════════════════════════════════════════════════╝${C_RESET}"
}

banner

DNF_CONF="$(detect_dnf_conf)"

note "Host:               $(detect_hostname)"
note "OS:                 $(detect_fedora_pretty)"
note "Kernel:             $(detect_kernel)"
note "Arch:               $(detect_arch)"
note "Run id:             ${FUE_RUN_ID}"
note "DNF binary:         ${FUE_DNF}"
note "DNF config:         ${DNF_CONF}"
note "CPU cores total:    ${CPU_CORES}"
note "CPU load (1m):      ${LOAD1}"
note "Worker cores:       ${JOBS} (policy ${EFFECTIVE_MIN_CPU_WORKERS}-${EFFECTIVE_MAX_CPU_WORKERS})"
note "Link speed (Mb/s):  ${LINK_SPEED_MBPS_DISPLAY}"
note "Theoretical streams: ${THEORETICAL_PARALLEL_CAP}"
note "Parallel downloads: ${MAX_PARALLEL_DOWNLOADS} (${STREAM_UTILIZATION_PERCENT}% of theoretical)"
if (( DRY_RUN == 1 )); then
  warn "DRY-RUN — no system changes will be made"
fi
[[ -n "$CPU_WORKER_LIMIT_NOTE" ]] && warn "$CPU_WORKER_LIMIT_NOTE"
hr

telemetry_set version "$FUE_VERSION"
telemetry_set started_at "$(iso_now)"
telemetry_set fedora_version "$(detect_fedora_version)"
telemetry_set kernel "$(detect_kernel)"
telemetry_set jobs "$JOBS"
telemetry_set max_parallel_downloads "$MAX_PARALLEL_DOWNLOADS"
telemetry_set dry_run "$DRY_RUN"

# ---------- Lock + preflight ----------
acquire_lock || exit "$?"

run_preflight "$FUE_DNF" || exit 1

if (( DRY_RUN == 1 )); then
  log_step "Dry-run — exiting before mutations"
  log_info "Would tune: ${DNF_CONF} (max_parallel_downloads=${MAX_PARALLEL_DOWNLOADS}, etc.)"
  log_info "Would tune ${FUE_REPO_DIR}/*.repo (PREFER_MIRRORS=${PREFER_MIRRORS})"
  log_info "Would run: ${FUE_DNF} upgrade --refresh --best --allowerasing -y ..."
  log_info "Would clean: autoremove + old kernels + cached packages"
  exit 0
fi

# ---------- DNF tuning ----------
ttl "Tuning $(basename "$FUE_DNF")"
tune_dnf_config "$DNF_CONF" \
  "$MAX_PARALLEL_DOWNLOADS" "$INSTALLONLY_LIMIT" "$FASTESTMIRROR" \
  "$SKIP_IF_UNAVAILABLE" "$RETRIES" "$TIMEOUT" "$MINRATE"
ok "Config updated at $DNF_CONF"
hr

# ---------- Repo tuning ----------
if [[ "$PREFER_MIRRORS" == "1" ]]; then
  ttl "Mirror failover (parallel, safe, bounded)"
  tune_repo_files "$JOBS" "$SKIP_IF_UNAVAILABLE"
  hr
else
  note "PREFER_MIRRORS=0 — skipping mirrorlist preference pass"
  hr
fi

# ---------- Metadata ----------
ttl "Refreshing metadata"
dnf_clean_expire_cache
run_dnf_with_repo_fallback "Metadata refresh" bash -c \
  "if \"${FUE_DNF}\" makecache --help 2>&1 | grep -q -- ' --timer'; then exec \"${FUE_DNF}\" makecache --timer -q; else exec \"${FUE_DNF}\" makecache -q; fi"
ok "Metadata refreshed"

# ---------- Upgrade ----------
ttl "Applying updates ($(basename "$FUE_DNF") upgrade)"
DNF_UPDATE_ARGS=(
  --refresh --best --allowerasing -y
  "--setopt=max_parallel_downloads=${MAX_PARALLEL_DOWNLOADS}"
  "--setopt=skip_if_unavailable=${SKIP_IF_UNAVAILABLE_BOOL}"
)
START_UPGRADE_EPOCH="$(epoch_now)"
run_dnf_with_repo_fallback "Upgrade transaction" "$FUE_DNF" upgrade "${DNF_UPDATE_ARGS[@]}"
END_UPGRADE_EPOCH="$(epoch_now)"
telemetry_set upgrade_seconds "$(( END_UPGRADE_EPOCH - START_UPGRADE_EPOCH ))"
ok "$(basename "$FUE_DNF") upgrade complete"

if [[ "$RUN_UPDATE_SWEEP" == "1" ]]; then
  ttl "$(basename "$FUE_DNF") update sweep"
  run_dnf_with_repo_fallback "Update sweep" "$FUE_DNF" update "${DNF_UPDATE_ARGS[@]}"
  ok "$(basename "$FUE_DNF") update sweep complete"
else
  note "RUN_UPDATE_SWEEP=0 — skipping (upgrade == update in DNF5)"
fi
hr

print_repo_coverage_summary

# ---------- Cleanup ----------
ttl "Cleaning up"
dnf_autoremove
dnf_remove_old_installonly
dnf_clean_packages
ok "Cleanup complete"
hr

emit_postflight_summary "$FUE_DNF"

ok "All done (run id ${FUE_RUN_ID})"
log_info "Telemetry: ${FUE_TELEMETRY_FILE}"
log_info "Log:       ${FUE_LOG_FILE}"
