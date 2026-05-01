#!/usr/bin/env bash
# scripts/perf-bench.sh — controlled-input perf bench for the SLOs in
# docs/SLO.md. Emits one JSON object per run + an aggregate footer with
# p50/p95/p99 across runs.
#
# Usage:
#   scripts/perf-bench.sh                          # all benches, JSON to stdout
#   scripts/perf-bench.sh metadata-refresh         # one bench
#   scripts/perf-bench.sh full-run
#   scripts/perf-bench.sh sizing-decision
#   PERF_BENCH_RUNS=20 scripts/perf-bench.sh       # more samples
#
# Hermetic by design: uses tests/mocks/dnf5 and a tmp repos/ dir. Never
# touches the network, the rpm DB, or /etc/yum.repos.d. Safe to run as
# any UID.

set -Eeuo pipefail
IFS=$'\n\t'

PROJECT_ROOT="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"

PERF_BENCH_RUNS="${PERF_BENCH_RUNS:-5}"
if ! [[ "$PERF_BENCH_RUNS" =~ ^[0-9]+$ ]] || (( PERF_BENCH_RUNS < 1 )); then
  printf 'PERF_BENCH_RUNS must be a positive integer, got: %s\n' "$PERF_BENCH_RUNS" >&2
  exit 64
fi

TMPDIR_BASE="$(mktemp -d /tmp/fue-bench.XXXXXX)"
cleanup_bench() { rm -rf "$TMPDIR_BASE" 2>/dev/null || true; }
trap cleanup_bench EXIT

# Set up an isolated environment that the orchestrator + libs can run in
# without touching /etc, /var/log, /var/lock, or /usr/bin/dnf5.
setup_env() {
  local mock_bin="${TMPDIR_BASE}/bin"
  local repo_dir="${TMPDIR_BASE}/repos"
  local log_dir="${TMPDIR_BASE}/log"
  local lock_file="${TMPDIR_BASE}/lock"

  mkdir -p "$mock_bin" "$repo_dir" "$log_dir"
  cp "${PROJECT_ROOT}/tests/mocks/dnf5" "${mock_bin}/dnf5"
  chmod 0755 "${mock_bin}/dnf5"

  # Three minimal repo files for the parallel-tune codepath.
  cat >"${repo_dir}/fedora.repo" <<'REPO'
[fedora]
name=Fedora $releasever - $basearch
metalink=https://mirrors.fedoraproject.org/metalink?repo=fedora-$releasever&arch=$basearch
enabled=1
gpgcheck=1
REPO
  cat >"${repo_dir}/updates.repo" <<'REPO'
[updates]
name=Fedora $releasever - $basearch - Updates
metalink=https://mirrors.fedoraproject.org/metalink?repo=updates-released-f$releasever&arch=$basearch
enabled=1
gpgcheck=1
REPO
  cat >"${repo_dir}/extras.repo" <<'REPO'
[extras]
name=Fedora $releasever - $basearch - Extras
baseurl=https://example.invalid/extras/
enabled=1
gpgcheck=0
REPO

  export FUE_DNF="${mock_bin}/dnf5"
  export FUE_REPO_DIR="$repo_dir"
  export FUE_LOG_DIR="$log_dir"
  export FUE_LOCK_FILE="$lock_file"
  export FUE_LOG_FILE_ENABLED=0
  export FUE_LOG_JOURNALD=0
  export FUE_PREFLIGHT_FATAL=0
  export FUE_PREFLIGHT_NETWORK=0
  export FUE_ALLOW_PACKAGEKIT=1
  export FUE_LOG_LEVEL=warn
}

# High-resolution wall-clock in milliseconds (integer).
# Use 10# prefix to force base-10 — date %N can have leading zeros that
# bash arithmetic would otherwise interpret as octal. Local IFS for the
# read because the script's top-level IFS excludes plain space.
now_ms() {
  local s ns IFS=' '
  read -r s ns < <(date -u +'%s %N')
  printf '%d' "$(( 10#${s} * 1000 + 10#${ns:-0} / 1000000 ))"
}

# Shared sourcing for the sizing benchmark — load just core + system,
# nothing else, to isolate the sizing path.
source_sizing_only() {
  export FUE_PROJECT_ROOT="$PROJECT_ROOT"
  export FUE_LIB_DIR="${PROJECT_ROOT}/lib"
  # shellcheck source=lib/core.sh
  source "${FUE_LIB_DIR}/core.sh"
  # shellcheck source=lib/system.sh
  source "${FUE_LIB_DIR}/system.sh"
}

# ---------------------------------------------------------------------------
# Bench 1: metadata refresh — exercises lib/dnf.sh against the mock dnf5.
# ---------------------------------------------------------------------------
bench_metadata_refresh() {
  setup_env
  export FUE_PROJECT_ROOT="$PROJECT_ROOT"
  export FUE_LIB_DIR="${PROJECT_ROOT}/lib"
  # shellcheck source=lib/core.sh
  source "${FUE_LIB_DIR}/core.sh"
  # shellcheck source=lib/log.sh
  source "${FUE_LIB_DIR}/log.sh"
  # shellcheck source=lib/dnf.sh
  source "${FUE_LIB_DIR}/dnf.sh"

  local start end
  start="$(now_ms)"
  dnf_clean_expire_cache >/dev/null 2>&1 || true
  dnf_makecache >/dev/null 2>&1 || true
  end="$(now_ms)"
  printf '%d' "$(( end - start ))"
}

# ---------------------------------------------------------------------------
# Bench 2: full run — full orchestrator dry-run path. Captures wall-clock,
# orchestrator overhead is everything since dnf upgrade isn't called.
# ---------------------------------------------------------------------------
bench_full_run() {
  setup_env
  local start end
  start="$(now_ms)"
  "${PROJECT_ROOT}/bin/elegant-updater.sh" \
    --dry-run --no-banner --no-journald >/dev/null 2>&1 || true
  end="$(now_ms)"
  printf '%d' "$(( end - start ))"
}

# ---------------------------------------------------------------------------
# Bench 3: sizing decision — calc_jobs + link-speed probe in isolation.
# ---------------------------------------------------------------------------
bench_sizing_decision() {
  source_sizing_only
  local cores load minw maxw
  local start end
  start="$(now_ms)"
  cores="$(detect_cpu_cores)"
  load="$(detect_loadavg_1m)"
  minw=10; maxw=20
  calc_jobs_from_load "$cores" "$load" "$minw" "$maxw" >/dev/null
  detect_fastest_link_speed_mbps >/dev/null
  end="$(now_ms)"
  printf '%d' "$(( end - start ))"
}

# ---------------------------------------------------------------------------
# Stats: compute p50/p95/p99 from a sorted list of integers.
# ---------------------------------------------------------------------------
percentile() {
  # $1 = sorted file, $2 = pXX as integer (50, 95, 99)
  awk -v p="$2" '
    BEGIN{n=0}
    {a[++n]=$1}
    END {
      if (n == 0) { print 0; exit }
      idx = int((p / 100) * n + 0.5)
      if (idx < 1) idx = 1
      if (idx > n) idx = n
      print a[idx]
    }
  ' "$1"
}

run_bench() {
  local name="$1" fn="$2"
  local i sample
  local samples_file="${TMPDIR_BASE}/${name}.samples"
  : > "$samples_file"
  for (( i = 1; i <= PERF_BENCH_RUNS; i++ )); do
    sample="$( "$fn" )"
    printf '%d\n' "$sample" >> "$samples_file"
  done
  sort -n "$samples_file" > "${samples_file}.sorted"
  local p50 p95 p99 mn mx
  p50="$(percentile "${samples_file}.sorted" 50)"
  p95="$(percentile "${samples_file}.sorted" 95)"
  p99="$(percentile "${samples_file}.sorted" 99)"
  mn="$(head -1 "${samples_file}.sorted")"
  mx="$(tail -1 "${samples_file}.sorted")"
  printf '    "%s": {"runs": %d, "min_ms": %d, "p50_ms": %d, "p95_ms": %d, "p99_ms": %d, "max_ms": %d}' \
    "$name" "$PERF_BENCH_RUNS" "$mn" "$p50" "$p95" "$p99" "$mx"
}

emit_json() {
  local target="${1:-all}"
  local ts
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf '{\n'
  printf '  "schema": "fue-perf-bench/v1",\n'
  printf '  "ts": "%s",\n' "$ts"
  printf '  "host": "%s",\n' "$(hostname -s 2>/dev/null || hostname)"
  printf '  "fedora_version": "%s",\n' \
    "$(awk -F= '$1=="VERSION_ID"{gsub(/"/,"",$2); print $2}' /etc/os-release 2>/dev/null || echo unknown)"
  printf '  "bash_version": "%s",\n' "$BASH_VERSION"
  printf '  "runs": %d,\n' "$PERF_BENCH_RUNS"
  printf '  "results": {\n'
  local first=1
  if [[ "$target" == "all" || "$target" == "metadata-refresh" ]]; then
    (( first == 0 )) && printf ',\n'
    run_bench "metadata-refresh" bench_metadata_refresh
    first=0
  fi
  if [[ "$target" == "all" || "$target" == "full-run" ]]; then
    (( first == 0 )) && printf ',\n'
    run_bench "full-run" bench_full_run
    first=0
  fi
  if [[ "$target" == "all" || "$target" == "sizing-decision" ]]; then
    (( first == 0 )) && printf ',\n'
    run_bench "sizing-decision" bench_sizing_decision
    first=0
  fi
  printf '\n  }\n'
  printf '}\n'
}

# ---------------------------------------------------------------------------
# Compare mode: compare current bench against a baseline file. Exit 1 if
# any p99 regresses by more than PERF_BENCH_REGRESSION_PCT (default 15).
# Usage: scripts/perf-bench.sh compare <baseline.json> [current.json]
# ---------------------------------------------------------------------------
do_compare() {
  local baseline="$1" current="${2:-}"
  if [[ -z "$baseline" || ! -f "$baseline" ]]; then
    printf 'compare: baseline file not found: %s\n' "$baseline" >&2
    exit 64
  fi
  if ! command -v jq >/dev/null 2>&1; then
    printf 'compare: jq is required\n' >&2
    exit 1
  fi
  local current_file
  if [[ -n "$current" && -f "$current" ]]; then
    current_file="$current"
  else
    current_file="${TMPDIR_BASE}/current.json"
    emit_json all > "$current_file"
  fi

  local pct="${PERF_BENCH_REGRESSION_PCT:-15}"
  local rc=0
  local op base_p99 cur_p99 delta_pct
  for op in metadata-refresh full-run sizing-decision; do
    base_p99="$(jq -r ".results[\"${op}\"].p99_ms // empty" "$baseline" 2>/dev/null)"
    cur_p99="$(jq -r ".results[\"${op}\"].p99_ms // empty" "$current_file" 2>/dev/null)"
    if [[ -z "$base_p99" || -z "$cur_p99" ]]; then
      printf 'compare: missing data for %s (baseline=%s current=%s)\n' \
        "$op" "${base_p99:-NA}" "${cur_p99:-NA}" >&2
      continue
    fi
    if (( base_p99 == 0 )); then
      # Baseline is below the 1ms floor — only fail if current is > 100ms,
      # which would be a clear regression. Anything else is noise.
      if (( cur_p99 > 100 )); then
        printf 'REGRESS %s: baseline=%dms current=%dms (baseline floor)\n' \
          "$op" "$base_p99" "$cur_p99" >&2
        rc=1
      else
        printf 'OK      %s: baseline=%dms current=%dms (under floor)\n' \
          "$op" "$base_p99" "$cur_p99"
      fi
      continue
    fi
    delta_pct=$(( (cur_p99 - base_p99) * 100 / base_p99 ))
    if (( delta_pct > pct )); then
      printf 'REGRESS %s: baseline=%dms current=%dms (+%d%%, threshold %d%%)\n' \
        "$op" "$base_p99" "$cur_p99" "$delta_pct" "$pct" >&2
      rc=1
    else
      printf 'OK      %s: baseline=%dms current=%dms (%+d%%, threshold %d%%)\n' \
        "$op" "$base_p99" "$cur_p99" "$delta_pct" "$pct"
    fi
  done
  exit "$rc"
}

# ---------------------------------------------------------------------------
# Entry
# ---------------------------------------------------------------------------
case "${1:-all}" in
  all|metadata-refresh|full-run|sizing-decision)
    emit_json "${1:-all}"
    ;;
  compare)
    shift
    do_compare "$@"
    ;;
  -h|--help|help)
    sed -n '2,18p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
    ;;
  *)
    printf 'unknown bench: %s\n' "$1" >&2
    sed -n '2,18p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' >&2
    exit 64
    ;;
esac
