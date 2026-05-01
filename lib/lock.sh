#!/usr/bin/env bash
# lib/lock.sh — flock-based concurrency control.

if [[ -n "${__FUE_LOCK_LOADED__:-}" ]]; then return 0; fi
__FUE_LOCK_LOADED__=1

# shellcheck source=lib/log.sh
source "${FUE_LIB_DIR:?}/log.sh"

FUE_LOCK_FILE="${FUE_LOCK_FILE:-/var/lock/elegant-updater.lock}"
__FUE_LOCK_FD=

acquire_lock() {
  local timeout="${1:-0}"
  if ! command -v flock >/dev/null 2>&1; then
    log_warn "flock not available — concurrent runs will not be detected"
    return 0
  fi

  exec {__FUE_LOCK_FD}>"$FUE_LOCK_FILE" 2>/dev/null || {
    log_warn "Cannot create lock file $FUE_LOCK_FILE; running unlocked"
    return 0
  }

  if (( timeout > 0 )); then
    if ! flock -w "$timeout" "$__FUE_LOCK_FD"; then
      log_error "Another elegant-updater run is in progress (lock $FUE_LOCK_FILE)"
      return 11
    fi
  else
    if ! flock -n "$__FUE_LOCK_FD"; then
      log_error "Another elegant-updater run is in progress (lock $FUE_LOCK_FILE)"
      return 11
    fi
  fi

  { printf '%d %s\n' "$$" "$(iso_now)" >&"$__FUE_LOCK_FD"; } 2>/dev/null || true
  return 0
}

release_lock() {
  if [[ -n "$__FUE_LOCK_FD" ]]; then
    eval "exec ${__FUE_LOCK_FD}>&-"
    __FUE_LOCK_FD=
  fi
}
