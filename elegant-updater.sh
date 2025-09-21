#!/usr/bin/env bash
# fedora42-autoupdate.sh — Simple unattended updater (dnf5 + delta RPMs)
# No restart check, no log files.
# Usage: sudo ./fedora42-autoupdate.sh

set -Eeuo pipefail

# ---------- Styling ----------
if [[ -t 1 ]]; then
  C_RESET="$(printf '\033[0m')"
  C_DIM="$(printf '\033[2m')"
  C_BOLD="$(printf '\033[1m')"
  C_HL="$(printf '\033[1;36m')"      # cyan
  C_OK="$(printf '\033[1;32m')"      # green
  C_WARN="$(printf '\033[1;33m')"    # yellow
  C_ERR="$(printf '\033[1;31m')"     # red
  C_BLUE="$(printf '\033[34m')"
else
  C_RESET=""; C_DIM=""; C_BOLD=""; C_HL=""; C_OK=""; C_WARN=""; C_ERR=""; C_BLUE=""
fi

hr()   { printf "%s\n" "${C_DIM}────────────────────────────────────────────────────────${C_RESET}"; }
ttl()  { printf "%s\n" "${C_HL}==> $*${C_RESET}"; }
ok()   { printf "%s\n" "${C_OK}✔${C_RESET} $*"; }
warn() { printf "%s\n" "${C_WARN}▲${C_RESET} $*"; }
err()  { printf "%s\n" "${C_ERR}✖${C_RESET} $*"; }
note() { printf "%s\n" "${C_DIM}•${C_RESET} $*"; }

# ---------- Tunables ----------
DNF=${DNF:-/usr/bin/dnf5}
# Prefer dnf5.conf on DNF5 hosts, otherwise fall back to legacy path.
DNF_CONF=${DNF_CONF:-}
if [[ -z "${DNF_CONF}" ]]; then
  if [[ -f /etc/dnf/dnf5.conf ]]; then
    DNF_CONF=/etc/dnf/dnf5.conf
  else
    DNF_CONF=/etc/dnf/dnf.conf
  fi
fi

MAX_PARALLEL_DOWNLOADS=${MAX_PARALLEL_DOWNLOADS:-10}
INSTALLONLY_LIMIT=${INSTALLONLY_LIMIT:-3}

# ---------- Checks ----------
[[ $EUID -eq 0 ]] || { err "Run as root (sudo)."; exit 1; }
command -v "$DNF" >/dev/null || { err "dnf5 not found at $DNF"; exit 1; }

# ---------- Header ----------
# Leading \r ensures we start at column 0 even if a prior carriage return/progress line is active.
printf "\r%s\n\n" "${C_BOLD}${C_BLUE}Fedora 42 — Auto Update${C_RESET}"
note "Host: $(hostname -f 2>/dev/null || hostname)"
note "Kernel: $(uname -r)"
hr

# ---------- dnf tuning ----------
ttl "Tuning dnf5"
conf="$DNF_CONF"
[[ -e "$conf" ]] || { install -m 0644 -o root -g root /dev/null "$conf"; }

ensure_kv() {
  local key="$1" val="$2"
  local tmp="${conf}.tmp.$$"

  # Build a safe updated file to tmp, then mv atomically.
  awk -v key="$key" -v val="$val" '
    BEGIN{updated=0; inmain=0}
    /^\[main\]/ { print; inmain=1; next }
    {
      if (inmain && $0 ~ "^[[:space:]]*"key"[[:space:]]*=") {
        print key"="val
        # skip any existing line with this key
        updated=1
        # consume following line only if it would have been the old kv (already matched)
        next
      }
      print
    }
    END{
      if (!inmain) {
        print "[main]"
        inmain=1
      }
      if (!updated) {
        print key"="val
      }
    }
  ' "$conf" > "$tmp"

  # Replace file preserving owner/mode if possible
  # shellcheck disable=SC2015
  install -m "$(stat -c '%a' "$conf" 2>/dev/null || echo 0644)" -o root -g root "$tmp" "$tmp" >/dev/null 2>&1 || true
  mv -f "$tmp" "$conf"
}

# Common knobs; write both fastestmirror keys for cross-compat safety.
ensure_kv deltarpm true
ensure_kv fastestmirror true
ensure_kv enable_fastestmirror true
ensure_kv max_parallel_downloads "${MAX_PARALLEL_DOWNLOADS}"
ensure_kv installonly_limit "${INSTALLONLY_LIMIT}"
ok "Config updated at $conf"
hr

# ---------- Update ----------
ttl "Refreshing metadata"
# Clear expired metadata only
"$DNF" clean expire-cache >/dev/null 2>&1 || true

# Use makecache; if --timer exists (DNF4), use it, else plain makecache (DNF5).
if "$DNF" makecache --help 2>&1 | grep -q -- ' --timer'; then
  "$DNF" makecache --timer -q || true
else
  "$DNF" makecache -q || true
fi
ok "Metadata refreshed"

ttl "Applying updates"
"$DNF" upgrade --refresh --best --allowerasing -y
ok "Updates applied"
hr

# ---------- Cleanup ----------
ttl "Cleaning up"
"$DNF" autoremove -y || true

# Remove old installonly packages (old kernels, etc.) in a DNF5-friendly way.
# Try the DNF5 idiom first; fall back if needed.
if "$DNF" repoquery --help 2>&1 | grep -q -- '--installonly'; then
  if "$DNF" repoquery --installonly | grep -q .; then
    "$DNF" remove installonly -y || true
  fi
else
  if "$DNF" repoquery installonly | grep -q .; then
    "$DNF" remove installonly -y || true
  fi
fi

"$DNF" clean all || true
ok "Cleanup complete"

hr
ok "All done"
