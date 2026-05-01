#!/usr/bin/env bash
# lib/dnf.sh — dnf5 operations: config tuning, upgrade, cleanup.

if [[ -n "${__FUE_DNF_LOADED__:-}" ]]; then return 0; fi
__FUE_DNF_LOADED__=1

# shellcheck source=lib/log.sh
source "${FUE_LIB_DIR:?}/log.sh"

FUE_DNF="${FUE_DNF:-${DNF:-/usr/bin/dnf5}}"

# Pick conf file: dnf5.conf if present, else dnf.conf.
detect_dnf_conf() {
  local override="${FUE_DNF_CONF:-${DNF_CONF:-}}"
  if [[ -n "$override" ]]; then echo "$override"; return; fi
  if [[ -f /etc/dnf/dnf5.conf ]]; then echo /etc/dnf/dnf5.conf
  else echo /etc/dnf/dnf.conf; fi
}

# Atomic write key=value into [main] of conf.
ensure_kv() {
  local conf="$1" key="$2" val="$3"
  local tmp="${conf}.tmp.$$"
  [[ -e "$conf" ]] || install -m 0644 -o root -g root /dev/null "$conf"
  awk -v key="$key" -v val="$val" '
    BEGIN{updated=0; inmain=0}
    /^\[main\]/ { print; inmain=1; next }
    {
      if (inmain && $0 ~ "^[[:space:]]*"key"[[:space:]]*=") {
        print key"="val
        updated=1
        next
      }
      print
    }
    END{
      if (!inmain) { print "[main]"; inmain=1 }
      if (!updated) { print key"="val }
    }
  ' "$conf" > "$tmp"
  install -m "$(stat -c '%a' "$conf" 2>/dev/null || echo 0644)" \
    -o root -g root "$tmp" "$conf" >/dev/null 2>&1 \
    || mv -f "$tmp" "$conf"
  rm -f "$tmp" 2>/dev/null || true
}

tune_dnf_config() {
  local conf="$1"
  local max_par="$2" installonly="$3" fastest="$4" skip="$5"
  local retries="$6" timeout="$7" minrate="$8"

  ensure_kv "$conf" deltarpm           true
  ensure_kv "$conf" keepcache          false
  if [[ "$fastest" == "1" ]]; then
    ensure_kv "$conf" fastestmirror        true
    ensure_kv "$conf" enable_fastestmirror true
  else
    ensure_kv "$conf" fastestmirror        false
    ensure_kv "$conf" enable_fastestmirror false
  fi
  ensure_kv "$conf" max_parallel_downloads "$max_par"
  ensure_kv "$conf" installonly_limit       "$installonly"
  if [[ "$skip" == "1" ]]; then
    ensure_kv "$conf" skip_if_unavailable true
  else
    ensure_kv "$conf" skip_if_unavailable false
  fi
  ensure_kv "$conf" retries  "$retries"
  ensure_kv "$conf" timeout  "$timeout"
  ensure_kv "$conf" minrate  "$minrate"
}

dnf_makecache() {
  local -a extra=( "$@" )
  if "$FUE_DNF" makecache --help 2>&1 | grep -q -- ' --timer'; then
    "$FUE_DNF" makecache --timer -q "${extra[@]}"
  else
    "$FUE_DNF" makecache -q "${extra[@]}"
  fi
}

dnf_clean_expire_cache() {
  "$FUE_DNF" clean expire-cache >/dev/null 2>&1 || true
}

dnf_upgrade() {
  "$FUE_DNF" upgrade "$@"
}

dnf_update_sweep() {
  "$FUE_DNF" update "$@"
}

dnf_autoremove() {
  "$FUE_DNF" autoremove -y || true
}

dnf_clean_packages() {
  "$FUE_DNF" clean packages || true
}

# Remove old installonly packages (kernels), DNF5 + DNF4 friendly.
dnf_remove_old_installonly() {
  if "$FUE_DNF" repoquery --help 2>&1 | grep -q -- '--installonly'; then
    if "$FUE_DNF" repoquery --installonly | grep -q .; then
      "$FUE_DNF" remove installonly -y || true
    fi
  else
    if "$FUE_DNF" repoquery installonly 2>/dev/null | grep -q .; then
      "$FUE_DNF" remove installonly -y || true
    fi
  fi
}
