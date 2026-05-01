#!/usr/bin/env bash
# lib/postflight.sh — post-execution checks + summary.

if [[ -n "${__FUE_POSTFLIGHT_LOADED__:-}" ]]; then return 0; fi
__FUE_POSTFLIGHT_LOADED__=1

# shellcheck source=lib/log.sh
source "${FUE_LIB_DIR:?}/log.sh"

# Returns 0 if reboot required, 1 if not, 2 if unknown.
detect_reboot_needed() {
  local dnf_path="${1:-/usr/bin/dnf5}"

  if [[ -f /var/run/reboot-required ]]; then
    return 0
  fi

  if command -v "$dnf_path" >/dev/null 2>&1; then
    if "$dnf_path" needs-restarting --reboothint >/dev/null 2>&1; then
      local rc=$?
      [[ "$rc" == "0" ]] && return 1
      [[ "$rc" == "1" ]] && return 0
    fi
  fi

  # Fallback: kernel mismatch (running != newest installed)
  local running newest
  running="$(uname -r)"
  if command -v rpm >/dev/null 2>&1; then
    newest="$(rpm -q --queryformat '%{VERSION}-%{RELEASE}.%{ARCH}\n' kernel 2>/dev/null \
      | sort -V | tail -1)"
    if [[ -n "$newest" && "$running" != "$newest" ]]; then
      return 0
    fi
  fi
  return 1
}

emit_postflight_summary() {
  local dnf_path="${1:-/usr/bin/dnf5}"

  log_step "Post-flight"

  if detect_reboot_needed "$dnf_path"; then
    log_warn "Reboot required (kernel/glibc/critical lib updated)"
    telemetry_set reboot_needed true
  else
    log_ok "No reboot required"
    telemetry_set reboot_needed false
  fi

  # Last transaction summary
  if command -v "$dnf_path" >/dev/null 2>&1; then
    local last_id
    last_id="$("$dnf_path" history list 2>/dev/null | awk 'NR==3 { print $1 }')"
    if [[ -n "$last_id" && "$last_id" =~ ^[0-9]+$ ]]; then
      log_info "Last transaction id: ${last_id}"
      telemetry_set last_tx_id "$last_id"
    fi
  fi

  hr
}
