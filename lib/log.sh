#!/usr/bin/env bash
# lib/log.sh — structured + colored logging, journald, telemetry.

if [[ -n "${__FUE_LOG_LOADED__:-}" ]]; then return 0; fi
__FUE_LOG_LOADED__=1

# shellcheck source=lib/core.sh
source "${FUE_LIB_DIR:?FUE_LIB_DIR unset}/core.sh"

# ---------- Configuration ----------
FUE_LOG_LEVEL="${FUE_LOG_LEVEL:-${LOG_LEVEL:-info}}"
FUE_LOG_FORMAT="${FUE_LOG_FORMAT:-${LOG_FORMAT:-text}}"
FUE_LOG_JOURNALD="${FUE_LOG_JOURNALD:-${LOG_JOURNALD:-1}}"
FUE_LOG_DIR="${FUE_LOG_DIR:-/var/log/elegant-updater}"
FUE_LOG_FILE_ENABLED="${FUE_LOG_FILE_ENABLED:-1}"
FUE_RUN_ID="${FUE_RUN_ID:-$(generate_run_id)}"
FUE_LOG_FILE="${FUE_LOG_FILE:-${FUE_LOG_DIR}/run-${FUE_RUN_ID}.log}"
FUE_TELEMETRY_FILE="${FUE_TELEMETRY_FILE:-${FUE_LOG_DIR}/run-${FUE_RUN_ID}.json}"
FUE_TELEMETRY_KV="${FUE_TELEMETRY_KV:-${FUE_LOG_DIR}/run-${FUE_RUN_ID}.kv}"

# Level numbers via case (assoc arrays don't survive subshells in some test harnesses).
__fue_level_num() {
  case "$1" in
    debug) echo 10 ;;
    info)  echo 20 ;;
    warn)  echo 30 ;;
    error) echo 40 ;;
    *)     echo 20 ;;
  esac
}

# ---------- Color setup ----------
if [[ -t 1 && "$FUE_LOG_FORMAT" == "text" ]]; then
  C_RESET="$(printf '\033[0m')"
  C_DIM="$(printf '\033[2m')"
  C_BOLD="$(printf '\033[1m')"
  C_HL="$(printf '\033[1;36m')"
  C_OK="$(printf '\033[1;32m')"
  C_WARN="$(printf '\033[1;33m')"
  C_ERR="$(printf '\033[1;31m')"
  C_PINK="$(printf '\033[1;35m')"
  C_NEON="$(printf '\033[1;96m')"
else
  C_RESET=""; C_DIM=""; C_BOLD=""; C_HL=""
  C_OK=""; C_WARN=""; C_ERR=""; C_PINK=""; C_NEON=""
fi
export C_RESET C_DIM C_BOLD C_HL C_OK C_WARN C_ERR C_PINK C_NEON

__fue_level_allowed() {
  local cur need
  cur="$(__fue_level_num "$FUE_LOG_LEVEL")"
  need="$(__fue_level_num "$1")"
  if (( need >= cur )); then return 0; fi
  return 1
}

__fue_ensure_log_dir() {
  [[ "$FUE_LOG_FILE_ENABLED" != "1" ]] && return 0
  if mkdir -p "$FUE_LOG_DIR" 2>/dev/null; then
    chmod 0750 "$FUE_LOG_DIR" 2>/dev/null || true
  else
    FUE_LOG_FILE_ENABLED=0
  fi
}

# JSON-escape a string (subset: \, ", control chars).
__fue_json_escape() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"
  s="${s//$'\r'/\\r}"
  s="${s//$'\t'/\\t}"
  printf '%s' "$s"
}

__fue_log_emit() {
  local level="$1" msg="$2"; shift 2
  __fue_level_allowed "$level" || return 0

  local ts
  ts="$(iso_now)"

  __fue_ensure_log_dir

  if [[ "$FUE_LOG_FORMAT" == "json" ]]; then
    local json
    json="$(printf '{"ts":"%s","run_id":"%s","level":"%s","msg":"%s"' \
      "$ts" "$FUE_RUN_ID" "$level" "$(__fue_json_escape "$msg")")"
    while (( $# >= 2 )); do
      json+="$(printf ',"%s":"%s"' "$1" "$(__fue_json_escape "$2")")"
      shift 2
    done
    json+="}"
    printf '%s\n' "$json"
    if [[ "$FUE_LOG_FILE_ENABLED" == "1" ]]; then
      printf '%s\n' "$json" >> "$FUE_LOG_FILE" 2>/dev/null || true
    fi
  else
    local prefix=""
    case "$level" in
      debug) prefix="${C_DIM}[debug]${C_RESET}" ;;
      info)  prefix="${C_DIM}•${C_RESET}" ;;
      warn)  prefix="${C_WARN}▲${C_RESET}" ;;
      error) prefix="${C_ERR}✖${C_RESET}" ;;
      ok)    prefix="${C_OK}✔${C_RESET}" ;;
      step)  prefix="${C_HL}==>${C_RESET}" ;;
    esac
    printf '%s %s\n' "$prefix" "$msg"
    if [[ "$FUE_LOG_FILE_ENABLED" == "1" ]]; then
      printf '%s [%s] %s\n' "$ts" "$level" "$msg" >> "$FUE_LOG_FILE" 2>/dev/null || true
    fi
  fi

  if [[ "$FUE_LOG_JOURNALD" == "1" ]] && command -v systemd-cat >/dev/null 2>&1; then
    printf '%s\n' "$msg" \
      | systemd-cat -t elegant-updater -p "$level" 2>/dev/null || true
  fi
}

log_debug() { __fue_log_emit debug "$*"; }
log_info()  { __fue_log_emit info  "$*"; }
log_warn()  { __fue_log_emit warn  "$*"; }
log_error() { __fue_log_emit error "$*"; }
log_step()  { __fue_log_emit step  "$*"; }
log_ok()    { __fue_log_emit ok    "$*"; }

# Compatibility wrappers preserving original API.
hr()   {
  if [[ "$FUE_LOG_FORMAT" == "text" ]]; then
    printf '%s\n' "${C_DIM}────────────────────────────────────────────────────────${C_RESET}"
  fi
}
ttl()  { log_step "$*"; }
ok()   { log_ok "$*"; }
warn() { log_warn "$*"; }
err()  { log_error "$*"; }
note() { log_info "$*"; }

# Telemetry: file-backed key/value store (subshell-safe).
__fue_telemetry_init() {
  __fue_ensure_log_dir
  [[ "$FUE_LOG_FILE_ENABLED" != "1" ]] && return 0
  if [[ ! -e "$FUE_TELEMETRY_KV" ]]; then
    : > "$FUE_TELEMETRY_KV" 2>/dev/null || FUE_LOG_FILE_ENABLED=0
  fi
}

telemetry_set() {
  local key="$1" val="$2"
  __fue_telemetry_init
  [[ "$FUE_LOG_FILE_ENABLED" != "1" ]] && return 0
  printf '%s\t%s\n' "$key" "$val" >> "$FUE_TELEMETRY_KV" 2>/dev/null || true
}

telemetry_inc() {
  local key="$1" by="${2:-1}"
  local cur=0
  __fue_telemetry_init
  [[ "$FUE_LOG_FILE_ENABLED" != "1" ]] && return 0
  if [[ -f "$FUE_TELEMETRY_KV" ]]; then
    cur="$(awk -F'\t' -v k="$key" '$1==k {v=$2} END{print (v?v:0)}' "$FUE_TELEMETRY_KV")"
  fi
  telemetry_set "$key" "$(( cur + by ))"
}

telemetry_flush() {
  [[ "$FUE_LOG_FILE_ENABLED" != "1" ]] && return 0
  [[ -f "$FUE_TELEMETRY_KV" ]] || return 0
  local tmp="${FUE_TELEMETRY_KV}.dedupe"
  awk -F'\t' 'NF >= 2 { kv[$1] = $2 } END { for (k in kv) print k "\t" kv[k] }' \
    "$FUE_TELEMETRY_KV" > "$tmp" 2>/dev/null || return 0
  mv -f "$tmp" "$FUE_TELEMETRY_KV"
  {
    printf '{"run_id":"%s","ts":"%s"' "$FUE_RUN_ID" "$(iso_now)"
    while IFS=$'\t' read -r k v; do
      [[ -z "$k" ]] && continue
      printf ',"%s":"%s"' "$(__fue_json_escape "$k")" "$(__fue_json_escape "$v")"
    done < "$FUE_TELEMETRY_KV"
    printf '}\n'
  } > "$FUE_TELEMETRY_FILE" 2>/dev/null || true
}
