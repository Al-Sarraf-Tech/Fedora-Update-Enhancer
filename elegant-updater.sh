#!/usr/bin/env bash
# fedora-autoupdate.sh — High-performance unattended updater (dnf5 + delta RPMs)
# Optimised for maximum parallelism: parallel downloads + parallel repo processing.
# Usage: sudo update

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
  C_PINK="$(printf '\033[1;35m')"    # magenta / pink
  C_NEON="$(printf '\033[1;96m')"    # bright cyan (neon)
else
  C_RESET=""; C_DIM=""; C_BOLD=""; C_HL=""; C_OK=""; C_WARN=""; C_ERR=""
  C_PINK=""; C_NEON=""
fi

hr()   { printf "%s\n" "${C_DIM}────────────────────────────────────────────────────────${C_RESET}"; }
ttl()  { printf "%s\n" "${C_HL}==> $*${C_RESET}"; }
ok()   { printf "%s\n" "${C_OK}✔${C_RESET} $*"; }
warn() { printf "%s\n" "${C_WARN}▲${C_RESET} $*"; }
err()  { printf "%s\n" "${C_ERR}✖${C_RESET} $*"; }
note() { printf "%s\n" "${C_DIM}•${C_RESET} $*"; }

# ---------- Helpers ----------
clamp_int() {
  local val="$1" lo="$2" hi="$3"
  if (( val < lo )); then
    echo "$lo"
  elif (( val > hi )); then
    echo "$hi"
  else
    echo "$val"
  fi
}

as_positive_int() {
  local raw="$1" fallback="$2"
  if [[ "$raw" =~ ^[0-9]+$ ]] && (( raw > 0 )); then
    echo "$raw"
  else
    echo "$fallback"
  fi
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

detect_fastest_link_speed_mbps() {
  local best=0
  local speed_file iface speed
  shopt -s nullglob
  for speed_file in /sys/class/net/*/speed; do
    iface="${speed_file%/speed}"
    iface="${iface##*/}"
    case "$iface" in
      lo|docker*|veth*|br-*|virbr*|tun*|tap*|wg*|zt*)
        continue
        ;;
    esac
    speed="$(cat "$speed_file" 2>/dev/null || true)"
    if [[ "$speed" =~ ^[0-9]+$ ]] && (( speed > best )); then
      best="$speed"
    fi
  done
  shopt -u nullglob
  echo "$best"
}

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

# Adaptive execution budget: keep at least 10 workers when available, scale to 20 on idle systems.
CPU_CORES="$(as_positive_int "$(nproc 2>/dev/null || echo 4)" 4)"
LOAD1="$(awk '{print $1}' /proc/loadavg 2>/dev/null || echo 0)"
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
if (( CPU_CORES < MIN_CPU_WORKERS )); then
  CPU_WORKER_LIMIT_NOTE="Host has fewer than ${MIN_CPU_WORKERS} cores; using ${CPU_CORES} workers max."
else
  CPU_WORKER_LIMIT_NOTE=""
fi

ADAPTIVE_JOBS="$(calc_jobs_from_load "$CPU_CORES" "$LOAD1" "$EFFECTIVE_MIN_CPU_WORKERS" "$EFFECTIVE_MAX_CPU_WORKERS")"
JOBS=${JOBS:-$ADAPTIVE_JOBS}
JOBS="$(clamp_int "$JOBS" "$EFFECTIVE_MIN_CPU_WORKERS" "$EFFECTIVE_MAX_CPU_WORKERS")"

# Network concurrency: run at 95% of the computed theoretical ceiling to avoid throttling/rate limits.
DNF_PARALLEL_CAP="$(as_positive_int "${DNF_PARALLEL_CAP:-20}" 20)"
STREAM_MBIT_PER_CONN="$(as_positive_int "${STREAM_MBIT_PER_CONN:-35}" 35)"
STREAM_UTILIZATION_PERCENT="$(as_positive_int "${STREAM_UTILIZATION_PERCENT:-95}" 95)"
if (( DNF_PARALLEL_CAP > 20 )); then
  DNF_PARALLEL_CAP=20
fi
if (( STREAM_UTILIZATION_PERCENT > 95 )); then
  STREAM_UTILIZATION_PERCENT=95
fi
LINK_SPEED_MBPS="$(detect_fastest_link_speed_mbps)"
if [[ "$LINK_SPEED_MBPS" =~ ^[0-9]+$ ]] && (( LINK_SPEED_MBPS > 0 )); then
  LINK_SPEED_MBPS_DISPLAY="$LINK_SPEED_MBPS"
else
  LINK_SPEED_MBPS_DISPLAY="unknown"
fi

CPU_STREAM_LIMIT=$(( JOBS * 2 ))
THEORETICAL_PARALLEL_CAP="$DNF_PARALLEL_CAP"
if (( CPU_STREAM_LIMIT < THEORETICAL_PARALLEL_CAP )); then
  THEORETICAL_PARALLEL_CAP="$CPU_STREAM_LIMIT"
fi
if [[ "$LINK_SPEED_MBPS" =~ ^[0-9]+$ ]] && (( LINK_SPEED_MBPS > 0 )) && (( STREAM_MBIT_PER_CONN > 0 )); then
  LINK_STREAM_LIMIT=$(( LINK_SPEED_MBPS / STREAM_MBIT_PER_CONN ))
  if (( LINK_STREAM_LIMIT > 0 )) && (( LINK_STREAM_LIMIT < THEORETICAL_PARALLEL_CAP )); then
    THEORETICAL_PARALLEL_CAP="$LINK_STREAM_LIMIT"
  fi
fi
if (( THEORETICAL_PARALLEL_CAP < 1 )); then
  THEORETICAL_PARALLEL_CAP=1
fi

ADAPTIVE_MAX_PARALLEL_DOWNLOADS=$(( THEORETICAL_PARALLEL_CAP * STREAM_UTILIZATION_PERCENT / 100 ))
if (( ADAPTIVE_MAX_PARALLEL_DOWNLOADS < 1 )); then
  ADAPTIVE_MAX_PARALLEL_DOWNLOADS=1
fi
MAX_PARALLEL_DOWNLOADS=${MAX_PARALLEL_DOWNLOADS:-$ADAPTIVE_MAX_PARALLEL_DOWNLOADS}
MAX_PARALLEL_DOWNLOADS="$(clamp_int "$MAX_PARALLEL_DOWNLOADS" 1 "$DNF_PARALLEL_CAP")"

REPO_DIR=${REPO_DIR:-/etc/yum.repos.d}
INSTALLONLY_LIMIT=${INSTALLONLY_LIMIT:-3}
FASTESTMIRROR=${FASTESTMIRROR:-1}
SKIP_IF_UNAVAILABLE=${SKIP_IF_UNAVAILABLE:-1}
RETRIES=${RETRIES:-6}
TIMEOUT=${TIMEOUT:-15}
MINRATE=${MINRATE:-100k}
PREFER_MIRRORS=${PREFER_MIRRORS:-1}
if [[ "$SKIP_IF_UNAVAILABLE" -eq 1 ]]; then
  SKIP_IF_UNAVAILABLE_BOOL=True
else
  SKIP_IF_UNAVAILABLE_BOOL=False
fi
if [[ "${SHOW_REPO_LIST:-1}" == "0" ]]; then
  SHOW_REPO_LIST=0
else
  SHOW_REPO_LIST=1
fi
# Default 0: dnf5 upgrade == dnf5 update; running both wastes a full solver+download pass
RUN_UPDATE_SWEEP=${RUN_UPDATE_SWEEP:-0}

# ---------- Checks ----------
[[ $EUID -eq 0 ]] || { err "Run as root (sudo)."; exit 1; }
command -v "$DNF" >/dev/null || { err "dnf5 not found at $DNF"; exit 1; }

# ---------- Header ----------
printf "\r\n%s\n\n" "${C_BOLD}${C_NEON}╔════════════════════════════════════════════════════════╗${C_RESET}"
printf "%s\n" "${C_PINK}  ⛭  ✦  ✧  Fedora 43 Update — Snake  ✦  ✧  ⛭${C_RESET}"
printf "%s\n" "${C_NEON}╚════════════════════════════════════════════════════════╝${C_RESET}"
note "Host:               $(hostname -f 2>/dev/null || hostname)"
note "Kernel:             $(uname -r)"
note "CPU cores total:    ${CPU_CORES}"
note "CPU load (1m):      ${LOAD1}"
note "Worker cores:       ${JOBS} (policy ${EFFECTIVE_MIN_CPU_WORKERS}-${EFFECTIVE_MAX_CPU_WORKERS})"
note "Link speed (Mb/s):  ${LINK_SPEED_MBPS_DISPLAY}"
note "Theoretical streams: ${THEORETICAL_PARALLEL_CAP}"
note "Parallel downloads: ${MAX_PARALLEL_DOWNLOADS} (${STREAM_UTILIZATION_PERCENT}% of theoretical)"
if [[ -n "$CPU_WORKER_LIMIT_NOTE" ]]; then
  warn "$CPU_WORKER_LIMIT_NOTE"
fi
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
        updated=1
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

  # shellcheck disable=SC2015
  install -m "$(stat -c '%a' "$conf" 2>/dev/null || echo 0644)" -o root -g root "$tmp" "$conf" >/dev/null 2>&1 || true
  mv -f "$tmp" "$conf"
}

ensure_kv deltarpm                 true
ensure_kv keepcache                false   # don't accumulate RPMs on disk between runs
if [[ "$FASTESTMIRROR" -eq 1 ]]; then
  ensure_kv fastestmirror          true
  ensure_kv enable_fastestmirror   true
else
  ensure_kv fastestmirror          false
  ensure_kv enable_fastestmirror   false
fi
ensure_kv max_parallel_downloads   "${MAX_PARALLEL_DOWNLOADS}"
ensure_kv installonly_limit        "${INSTALLONLY_LIMIT}"
if [[ "$SKIP_IF_UNAVAILABLE" -eq 1 ]]; then
  ensure_kv skip_if_unavailable    true
else
  ensure_kv skip_if_unavailable    false
fi
ensure_kv retries                  "${RETRIES}"
ensure_kv timeout                  "${TIMEOUT}"
ensure_kv minrate                  "${MINRATE}"
ok "Config updated at $conf"
hr

# ---------- Repo safety + failover ----------
REPO_BACKUP_DIR=""
REPO_FILES_MODIFIED=0
REPO_ROLLBACK_APPLIED=0
declare -a DISABLED_REPOS=()
declare -a FAILED_REPOS=()
declare -a DISCOVERED_REPOS=()

cleanup_repo_backups() {
  if [[ -n "$REPO_BACKUP_DIR" && -d "$REPO_BACKUP_DIR" ]]; then
    rm -rf "$REPO_BACKUP_DIR"
  fi
}

trap cleanup_repo_backups EXIT

ensure_repo_backup_dir() {
  if [[ -z "$REPO_BACKUP_DIR" ]]; then
    REPO_BACKUP_DIR="$(mktemp -d /tmp/update-repo-backup.XXXXXX)"
  fi
}

snapshot_repo_files() {
  local file
  ensure_repo_backup_dir
  shopt -s nullglob
  for file in "$REPO_DIR"/*.repo; do
    cp -a "$file" "$REPO_BACKUP_DIR/$(basename "$file")"
  done
  shopt -u nullglob
}

restore_repo_backups() {
  local backup
  if [[ -z "$REPO_BACKUP_DIR" || ! -d "$REPO_BACKUP_DIR" ]]; then
    return 0
  fi
  shopt -s nullglob
  for backup in "$REPO_BACKUP_DIR"/*.repo; do
    cp -a "$backup" "$REPO_DIR/$(basename "$backup")"
  done
  shopt -u nullglob
  REPO_FILES_MODIFIED=0
  REPO_ROLLBACK_APPLIED=1
}

validate_repo_candidate() {
  local file="$1"
  grep -Eq '^[[:space:]]*\[[^]]+\][[:space:]]*$' "$file"
}

apply_repo_change() {
  local file="$1"
  local tmp="$2"

  if cmp -s "$file" "$tmp"; then
    rm -f "$tmp"
    return 1
  fi
  if ! validate_repo_candidate "$tmp"; then
    rm -f "$tmp"
    return 2
  fi

  chmod --reference="$file" "$tmp" 2>/dev/null || true
  chown --reference="$file" "$tmp" 2>/dev/null || true
  mv -f "$tmp" "$file"
  return 0
}

prefer_mirrorlist_in_repo() {
  local file="$1"
  local tmp="${file}.tmp.${BASHPID}"

  awk '
    function flush() {
      if (n == 0) return
      for (i = 1; i <= n; i++) {
        line = buf[i]
        if (has_mirror && line ~ /^[[:space:]]*baseurl[[:space:]]*=/ && line !~ /^[[:space:]]*#/) {
          print "#" line
        } else {
          print line
        }
      }
      n = 0
      has_mirror = 0
    }
    /^[[:space:]]*\[/ { flush() }
    {
      buf[++n] = $0
      if ($0 ~ /^[[:space:]]*(metalink|mirrorlist)[[:space:]]*=/ && $0 !~ /^[[:space:]]*#/) {
        has_mirror = 1
      }
    }
    END { flush() }
  ' "$file" > "$tmp"

  apply_repo_change "$file" "$tmp"
}

set_skip_if_unavailable_in_repo() {
  local file="$1"
  local tmp="${file}.tmp.${BASHPID}"
  local desired="False"
  if [[ "$SKIP_IF_UNAVAILABLE" -eq 1 ]]; then
    desired="True"
  fi

  awk -v desired="$desired" '
    function flush() {
      if (n == 0) return
      if (in_section && !found_skip) {
        buf[++n] = "skip_if_unavailable=" desired
      }
      for (i = 1; i <= n; i++) {
        line = buf[i]
        if (line ~ /^[[:space:]]*skip_if_unavailable[[:space:]]*=/ && line !~ /^[[:space:]]*#/) {
          print "skip_if_unavailable=" desired
        } else {
          print line
        }
      }
      n = 0
      found_skip = 0
    }
    /^[[:space:]]*\[/ {
      flush()
      in_section = 1
    }
    {
      buf[++n] = $0
      if ($0 ~ /^[[:space:]]*skip_if_unavailable[[:space:]]*=/ && $0 !~ /^[[:space:]]*#/) {
        found_skip = 1
      }
    }
    END { flush() }
  ' "$file" > "$tmp"

  apply_repo_change "$file" "$tmp"
}

string_in_array() {
  local needle="$1"
  shift
  local item
  for item in "$@"; do
    if [[ "$item" == "$needle" ]]; then
      return 0
    fi
  done
  return 1
}

collect_discovered_repos() {
  DISCOVERED_REPOS=()
  if [[ ! -d "$REPO_DIR" ]]; then
    return 0
  fi

  local -a repo_files=()
  shopt -s nullglob
  repo_files=("$REPO_DIR"/*.repo)
  shopt -u nullglob
  if (( ${#repo_files[@]} == 0 )); then
    return 0
  fi

  mapfile -t DISCOVERED_REPOS < <(
    awk -F'[][]' '/^[[:space:]]*\[[^]]+\][[:space:]]*$/{print $2}' "${repo_files[@]}" \
      | awk 'NF' \
      | sort -u
  )
}

print_repo_coverage_summary() {
  ttl "Repository coverage"
  collect_discovered_repos

  if (( ${#DISCOVERED_REPOS[@]} == 0 )); then
    warn "No repositories discovered in ${REPO_DIR}"
  else
    note "Discovered repositories: ${#DISCOVERED_REPOS[@]}"
    if [[ "$SHOW_REPO_LIST" -eq 1 ]]; then
      local repo
      for repo in "${DISCOVERED_REPOS[@]}"; do
        note "Repo: ${repo}"
      done
    fi
  fi

  if (( ${#FAILED_REPOS[@]} > 0 )); then
    warn "Repo failures observed: ${FAILED_REPOS[*]}"
  fi

  if (( ${#DISABLED_REPOS[@]} > 0 )); then
    warn "Temporary fallbacks active (disabled repos): ${DISABLED_REPOS[*]}"
    warn "Updates from those repos may be missing in this run. Fix them and rerun update."
  else
    ok "No repo fallbacks were required"
  fi

  if (( REPO_ROLLBACK_APPLIED == 1 )); then
    warn "Repo-file tuning changes were rolled back due repo retrieval failures."
  fi
  hr
}

repo_is_disabled() {
  local target="$1"
  string_in_array "$target" "${DISABLED_REPOS[@]}"
}

repo_is_failed() {
  local target="$1"
  string_in_array "$target" "${FAILED_REPOS[@]}"
}

has_repo_failure_signature() {
  local log_file="$1"
  grep -Eqi 'Failed to download metadata for repo|Cannot download repomd\.xml|All mirrors were tried|Cannot prepare internal mirrorlist|Curl error|Cannot download .* for repository' "$log_file"
}

extract_failed_repos() {
  local log_file="$1"
  {
    grep -oE "repo '[^']+'" "$log_file" | sed -E "s/^repo '([^']+)'$/\\1/" || true
    grep -oE "repository '[^']+'" "$log_file" | sed -E "s/^repository '([^']+)'$/\\1/" || true
  } | awk 'NF' | sort -u
}

run_dnf_with_repo_fallback() {
  local phase="$1"
  shift
  local -a base_cmd=( "$@" )
  local -a cmd=( "${base_cmd[@]}" )
  local repo

  for repo in "${DISABLED_REPOS[@]}"; do
    cmd+=( "--disablerepo=${repo}" )
  done

  local log_file
  log_file="$(mktemp)"
  if "${cmd[@]}" 2>&1 | tee "$log_file"; then
    rm -f "$log_file"
    return 0
  fi
  local rc=$?

  if ! has_repo_failure_signature "$log_file"; then
    rm -f "$log_file"
    return "$rc"
  fi

  mapfile -t failed_repos < <(extract_failed_repos "$log_file")
  rm -f "$log_file"
  if (( ${#failed_repos[@]} == 0 )); then
    return "$rc"
  fi

  if (( REPO_FILES_MODIFIED == 1 )) && (( REPO_ROLLBACK_APPLIED == 0 )); then
    warn "$phase hit repo failures after repo tuning; restoring repo backups before retry"
    restore_repo_backups
  fi

  local new_count=0
  for repo in "${failed_repos[@]}"; do
    if [[ -z "$repo" || "$repo" == "*" ]]; then
      continue
    fi
    if ! repo_is_failed "$repo"; then
      FAILED_REPOS+=("$repo")
    fi
    if ! repo_is_disabled "$repo"; then
      DISABLED_REPOS+=("$repo")
      ((new_count += 1))
    fi
  done

  if (( new_count == 0 )); then
    return "$rc"
  fi

  warn "$phase failed due to repo availability; retrying with temporary repo fallbacks"
  note "Temporarily disabled repos this run: ${DISABLED_REPOS[*]}"

  local -a retry_cmd=( "${base_cmd[@]}" )
  for repo in "${DISABLED_REPOS[@]}"; do
    retry_cmd+=( "--disablerepo=${repo}" )
  done
  "${retry_cmd[@]}"
}

if [[ "$PREFER_MIRRORS" -eq 1 ]]; then
  ttl "Mirror failover (parallel, safe, bounded)"
  if [[ ! -d "$REPO_DIR" ]]; then
    warn "Repo directory not found: $REPO_DIR"
  else
    snapshot_repo_files
    shopt -s nullglob
    declare -a _results=()
    _active=0

    for _repo in "$REPO_DIR"/*.repo; do
      _result_file="$(mktemp)"
      _results+=("$_result_file")
      (
        _c=0
        _e=0
        prefer_mirrorlist_in_repo "$_repo"; _rc=$?
        if [[ "$_rc" -eq 0 ]]; then
          _c=1
        elif [[ "$_rc" -eq 2 ]]; then
          _e=1
        fi
        set_skip_if_unavailable_in_repo "$_repo"; _rc=$?
        if [[ "$_rc" -eq 0 ]]; then
          _c=1
        elif [[ "$_rc" -eq 2 ]]; then
          _e=1
        fi
        echo "${_c}:${_e}" > "$_result_file"
      ) &
      _active=$((_active + 1))
      if (( _active >= JOBS )); then
        wait -n || true
        _active=$((_active - 1))
      fi
    done

    while (( _active > 0 )); do
      wait -n || true
      _active=$((_active - 1))
    done

    _changed=0
    _errors=0
    for _result_file in "${_results[@]}"; do
      if [[ -f "$_result_file" ]]; then
        IFS=':' read -r _c _e < "$_result_file" || true
        if [[ "${_c:-0}" == "1" ]]; then
          _changed=1
        fi
        if [[ "${_e:-0}" == "1" ]]; then
          _errors=1
        fi
      fi
      rm -f "$_result_file"
    done
    shopt -u nullglob

    if [[ "$_changed" -eq 1 ]]; then
      REPO_FILES_MODIFIED=1
      ok "Mirrorlist/metalink preferred and repo failover tuned"
    else
      note "No mirrorlist/metalink adjustments needed"
    fi
    if [[ "$_errors" -eq 1 ]]; then
      warn "One or more repo files failed safety validation and were left untouched"
    fi
  fi
  hr
else
  note "PREFER_MIRRORS=0 — skipping mirrorlist preference pass"
  hr
fi

# ---------- Update ----------
ttl "Refreshing metadata"
# Clear expired metadata only
"$DNF" clean expire-cache >/dev/null 2>&1 || true

# Use makecache; if --timer exists (DNF4), use it, else plain makecache (DNF5).
if "$DNF" makecache --help 2>&1 | grep -q -- ' --timer'; then
  run_dnf_with_repo_fallback "Metadata refresh" "$DNF" makecache --timer -q
else
  run_dnf_with_repo_fallback "Metadata refresh" "$DNF" makecache -q
fi
ok "Metadata refreshed"

ttl "Applying updates (dnf5 upgrade)"
# --setopt on CLI reinforces config values regardless of which conf file dnf5 loads.
DNF_UPDATE_ARGS=(
  --refresh --best --allowerasing -y
  "--setopt=max_parallel_downloads=${MAX_PARALLEL_DOWNLOADS}"
  "--setopt=skip_if_unavailable=${SKIP_IF_UNAVAILABLE_BOOL}"
)
run_dnf_with_repo_fallback "Upgrade transaction" "$DNF" upgrade "${DNF_UPDATE_ARGS[@]}"
ok "dnf5 upgrade complete"

if [[ "$RUN_UPDATE_SWEEP" -eq 1 ]]; then
  ttl "dnf5 update sweep"
  run_dnf_with_repo_fallback "Update sweep" "$DNF" update "${DNF_UPDATE_ARGS[@]}"
  ok "dnf5 update sweep complete"
else
  note "RUN_UPDATE_SWEEP=0 — skipping (dnf5 upgrade == dnf5 update in DNF5)"
fi
hr

print_repo_coverage_summary

# ---------- Cleanup ----------
ttl "Cleaning up"
"$DNF" autoremove -y || true

# Remove old installonly packages (old kernels, etc.) in a DNF5-friendly way.
if "$DNF" repoquery --help 2>&1 | grep -q -- '--installonly'; then
  if "$DNF" repoquery --installonly | grep -q .; then
    "$DNF" remove installonly -y || true
  fi
else
  if "$DNF" repoquery installonly | grep -q .; then
    "$DNF" remove installonly -y || true
  fi
fi

# Clean downloaded RPMs only; preserve metadata cache so the next run is faster.
"$DNF" clean packages || true
ok "Cleanup complete"

hr
ok "All done"
