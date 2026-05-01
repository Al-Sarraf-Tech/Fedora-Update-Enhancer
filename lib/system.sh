#!/usr/bin/env bash
# lib/system.sh — host detection (Fedora version, CPU, link speed).

if [[ -n "${__FUE_SYSTEM_LOADED__:-}" ]]; then return 0; fi
__FUE_SYSTEM_LOADED__=1

# shellcheck source=lib/core.sh
source "${FUE_LIB_DIR:?}/core.sh"

# Parse a key from /etc/os-release, stripping quotes.
__fue_os_release_value() {
  local key="$1"
  local file="${2:-/etc/os-release}"
  [[ -r "$file" ]] || { printf '\n'; return 0; }
  awk -F= -v k="$key" '$1 == k { gsub(/^"|"$/, "", $2); print $2; exit }' "$file"
}

detect_fedora_id() {
  __fue_os_release_value ID
}

detect_fedora_version() {
  __fue_os_release_value VERSION_ID
}

detect_fedora_pretty() {
  __fue_os_release_value PRETTY_NAME
}

detect_fedora_codename() {
  local val
  val="$(__fue_os_release_value VARIANT)"
  if [[ -z "$val" ]]; then
    val="$(__fue_os_release_value VERSION_CODENAME)"
  fi
  printf '%s' "$val"
}

detect_kernel() { uname -r; }
detect_arch()   { uname -m; }
detect_hostname() { hostname -f 2>/dev/null || hostname; }

detect_cpu_cores() { nproc 2>/dev/null || echo 4; }

detect_loadavg_1m() {
  awk '{print $1}' /proc/loadavg 2>/dev/null || echo 0
}

detect_fastest_link_speed_mbps() {
  local best=0 speed_file iface speed
  shopt -s nullglob
  for speed_file in /sys/class/net/*/speed; do
    iface="${speed_file%/speed}"
    iface="${iface##*/}"
    case "$iface" in
      lo|docker*|veth*|br-*|virbr*|tun*|tap*|wg*|zt*) continue ;;
    esac
    speed="$(cat "$speed_file" 2>/dev/null || true)"
    if [[ "$speed" =~ ^[0-9]+$ ]] && (( speed > best )); then
      best="$speed"
    fi
  done
  shopt -u nullglob
  echo "$best"
}

# Returns "Fedora <version>" or "Linux <id> <version>" if non-Fedora.
build_banner_subtitle() {
  local id ver pretty
  id="$(detect_fedora_id)"
  ver="$(detect_fedora_version)"
  pretty="$(detect_fedora_pretty)"
  if [[ "$id" == "fedora" && -n "$ver" ]]; then
    printf 'Fedora %s Update' "$ver"
  elif [[ -n "$pretty" ]]; then
    printf '%s Update' "$pretty"
  else
    printf 'System Update'
  fi
}

# Validate that we're on a supported Fedora release. Returns 0 if supported,
# 1 if probably-supported (warn), 2 if unsupported.
validate_fedora_supported() {
  local id ver
  id="$(detect_fedora_id)"
  ver="$(detect_fedora_version)"
  if [[ "$id" != "fedora" ]]; then
    return 2
  fi
  if ! [[ "$ver" =~ ^[0-9]+$ ]]; then
    return 2
  fi
  if (( ver < 41 )); then
    return 2
  fi
  if (( ver < 43 )); then
    return 1
  fi
  return 0
}
