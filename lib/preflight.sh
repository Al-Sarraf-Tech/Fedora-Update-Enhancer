#!/usr/bin/env bash
# lib/preflight.sh — pre-execution safety checks.

if [[ -n "${__FUE_PREFLIGHT_LOADED__:-}" ]]; then return 0; fi
__FUE_PREFLIGHT_LOADED__=1

# shellcheck source=lib/log.sh
source "${FUE_LIB_DIR:?}/log.sh"

FUE_MIN_FREE_VAR_MB="${FUE_MIN_FREE_VAR_MB:-2048}"
FUE_MIN_FREE_BOOT_MB="${FUE_MIN_FREE_BOOT_MB:-256}"
FUE_PREFLIGHT_NETWORK="${FUE_PREFLIGHT_NETWORK:-1}"
FUE_NETWORK_PROBE_HOST="${FUE_NETWORK_PROBE_HOST:-mirrors.fedoraproject.org}"
FUE_PREFLIGHT_FATAL="${FUE_PREFLIGHT_FATAL:-1}"

check_root() {
  if (( EUID != 0 )); then
    log_error "Run as root (sudo)"
    return 1
  fi
  return 0
}

check_dnf_present() {
  local dnf_path="$1"
  if ! command -v "$dnf_path" >/dev/null 2>&1; then
    log_error "dnf5 not found at $dnf_path"
    return 1
  fi
  return 0
}

# Returns free MB at the given mountpoint.
__fue_free_mb() {
  local path="$1"
  df -BM --output=avail "$path" 2>/dev/null \
    | awk 'NR==2 { gsub(/M/,""); print $1 }'
}

check_disk_space() {
  local var_free boot_free
  var_free="$(__fue_free_mb /var)"
  boot_free="$(__fue_free_mb /boot)"

  local ok=0
  if [[ -n "$var_free" ]] && (( var_free < FUE_MIN_FREE_VAR_MB )); then
    log_error "/var free space ${var_free}MB < required ${FUE_MIN_FREE_VAR_MB}MB"
    ok=1
  fi
  if [[ -n "$boot_free" ]] && (( boot_free < FUE_MIN_FREE_BOOT_MB )); then
    log_error "/boot free space ${boot_free}MB < required ${FUE_MIN_FREE_BOOT_MB}MB"
    ok=1
  fi
  if (( ok == 0 )); then
    log_debug "Disk space ok (/var ${var_free:-?}MB, /boot ${boot_free:-?}MB)"
  fi
  return "$ok"
}

# Detect another rpm/dnf process holding the rpmdb.
check_rpm_db_lock() {
  local lock_file="/var/lib/rpm/.rpm.lock"
  local lockdb_dir="/var/lib/dnf/rpmdb_indexes"
  if command -v fuser >/dev/null 2>&1 && [[ -e "$lock_file" ]]; then
    if fuser "$lock_file" >/dev/null 2>&1; then
      log_error "rpm database is locked by another process"
      return 1
    fi
  fi
  # Process scan fallback
  if pgrep -x dnf >/dev/null 2>&1 || pgrep -x dnf5 >/dev/null 2>&1 \
     || pgrep -x rpm >/dev/null 2>&1 || pgrep -x packagekitd >/dev/null 2>&1; then
    if [[ "${FUE_ALLOW_PACKAGEKIT:-0}" != "1" ]]; then
      log_error "Another package manager is running (dnf/dnf5/rpm/packagekit)"
      return 1
    fi
  fi
  log_debug "rpmdb lock clear"
  return 0
  # silence unused warning
  : "$lockdb_dir"
}

check_network() {
  [[ "$FUE_PREFLIGHT_NETWORK" != "1" ]] && return 0
  if command -v curl >/dev/null 2>&1; then
    if curl -fsS --max-time 5 -o /dev/null "https://${FUE_NETWORK_PROBE_HOST}/" 2>/dev/null; then
      log_debug "Network reachable: ${FUE_NETWORK_PROBE_HOST}"
      return 0
    fi
  fi
  if command -v getent >/dev/null 2>&1; then
    if getent hosts "$FUE_NETWORK_PROBE_HOST" >/dev/null 2>&1; then
      log_debug "DNS resolves ${FUE_NETWORK_PROBE_HOST} (no curl probe)"
      return 0
    fi
  fi
  log_warn "Cannot reach ${FUE_NETWORK_PROBE_HOST} — proceeding (may fail)"
  return 0
}

run_preflight() {
  local dnf_path="$1"
  local fail=0
  log_step "Pre-flight checks"
  check_root           || fail=1
  check_dnf_present "$dnf_path" || fail=1
  check_disk_space     || fail=1
  check_rpm_db_lock    || fail=1
  check_network        || true

  if (( fail != 0 )); then
    if [[ "$FUE_PREFLIGHT_FATAL" == "1" ]]; then
      log_error "Pre-flight failed; aborting"
      return 1
    else
      log_warn "Pre-flight had failures; FUE_PREFLIGHT_FATAL=0 → continuing"
    fi
  else
    log_ok "Pre-flight clean"
  fi
  return 0
}
