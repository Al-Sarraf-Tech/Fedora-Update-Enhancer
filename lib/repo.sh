#!/usr/bin/env bash
# lib/repo.sh — repo file mgmt + fallback wrapper for dnf.

if [[ -n "${__FUE_REPO_LOADED__:-}" ]]; then return 0; fi
__FUE_REPO_LOADED__=1

# shellcheck source=lib/log.sh
source "${FUE_LIB_DIR:?}/log.sh"
# shellcheck source=lib/dnf.sh
source "${FUE_LIB_DIR:?}/dnf.sh"

FUE_REPO_DIR="${FUE_REPO_DIR:-${REPO_DIR:-/etc/yum.repos.d}}"

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

ensure_repo_backup_dir() {
  if [[ -z "$REPO_BACKUP_DIR" ]]; then
    REPO_BACKUP_DIR="$(mktemp -d /tmp/elegant-updater-repo-backup.XXXXXX)"
  fi
}

snapshot_repo_files() {
  local file
  ensure_repo_backup_dir
  shopt -s nullglob
  for file in "$FUE_REPO_DIR"/*.repo; do
    cp -a "$file" "$REPO_BACKUP_DIR/$(basename "$file")"
  done
  shopt -u nullglob
}

restore_repo_backups() {
  local backup
  [[ -z "$REPO_BACKUP_DIR" || ! -d "$REPO_BACKUP_DIR" ]] && return 0
  shopt -s nullglob
  for backup in "$REPO_BACKUP_DIR"/*.repo; do
    cp -a "$backup" "$FUE_REPO_DIR/$(basename "$backup")"
  done
  shopt -u nullglob
  REPO_FILES_MODIFIED=0
  REPO_ROLLBACK_APPLIED=1
}

validate_repo_candidate() {
  grep -Eq '^[[:space:]]*\[[^]]+\][[:space:]]*$' "$1"
}

apply_repo_change() {
  local file="$1" tmp="$2"
  if cmp -s "$file" "$tmp"; then rm -f "$tmp"; return 1; fi
  if ! validate_repo_candidate "$tmp"; then rm -f "$tmp"; return 2; fi
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
        } else { print line }
      }
      n = 0; has_mirror = 0
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
  local file="$1" skip="$2"
  local tmp="${file}.tmp.${BASHPID}"
  local desired="False"
  [[ "$skip" == "1" ]] && desired="True"
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
        } else { print line }
      }
      n = 0; found_skip = 0
    }
    /^[[:space:]]*\[/ { flush(); in_section = 1 }
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

collect_discovered_repos() {
  DISCOVERED_REPOS=()
  [[ -d "$FUE_REPO_DIR" ]] || return 0
  local -a repo_files=()
  shopt -s nullglob
  repo_files=("$FUE_REPO_DIR"/*.repo)
  shopt -u nullglob
  (( ${#repo_files[@]} == 0 )) && return 0
  mapfile -t DISCOVERED_REPOS < <(
    awk -F'[][]' '/^[[:space:]]*\[[^]]+\][[:space:]]*$/{print $2}' "${repo_files[@]}" \
      | awk 'NF' | sort -u
  )
}

repo_is_disabled() { string_in_array "$1" "${DISABLED_REPOS[@]}"; }
repo_is_failed()   { string_in_array "$1" "${FAILED_REPOS[@]}"; }

has_repo_failure_signature() {
  grep -Eqi 'Failed to download metadata for repo|Cannot download repomd\.xml|All mirrors were tried|Cannot prepare internal mirrorlist|Curl error|Cannot download .* for repository' "$1"
}

extract_failed_repos() {
  {
    grep -oE "repo '[^']+'" "$1" | sed -E "s/^repo '([^']+)'$/\\1/" || true
    grep -oE "repository '[^']+'" "$1" | sed -E "s/^repository '([^']+)'$/\\1/" || true
  } | awk 'NF' | sort -u
}

run_dnf_with_repo_fallback() {
  local phase="$1"; shift
  local -a base_cmd=( "$@" )
  local -a cmd=( "${base_cmd[@]}" )
  local repo log_file rc
  for repo in "${DISABLED_REPOS[@]}"; do
    cmd+=( "--disablerepo=${repo}" )
  done
  log_file="$(mktemp)"
  if "${cmd[@]}" 2>&1 | tee "$log_file"; then
    rm -f "$log_file"; return 0
  fi
  rc="${PIPESTATUS[0]}"
  if ! has_repo_failure_signature "$log_file"; then
    rm -f "$log_file"; return "$rc"
  fi
  mapfile -t failed_repos < <(extract_failed_repos "$log_file")
  rm -f "$log_file"
  (( ${#failed_repos[@]} == 0 )) && return "$rc"

  if (( REPO_FILES_MODIFIED == 1 )) && (( REPO_ROLLBACK_APPLIED == 0 )); then
    log_warn "${phase} hit repo failures after repo tuning; restoring backups"
    restore_repo_backups
  fi

  local new_count=0
  for repo in "${failed_repos[@]}"; do
    [[ -z "$repo" || "$repo" == "*" ]] && continue
    repo_is_failed "$repo"   || FAILED_REPOS+=("$repo")
    if ! repo_is_disabled "$repo"; then
      DISABLED_REPOS+=("$repo")
      ((new_count += 1))
    fi
  done
  (( new_count == 0 )) && return "$rc"

  log_warn "${phase} retrying with fallbacks: ${DISABLED_REPOS[*]}"
  local -a retry_cmd=( "${base_cmd[@]}" )
  for repo in "${DISABLED_REPOS[@]}"; do
    retry_cmd+=( "--disablerepo=${repo}" )
  done
  "${retry_cmd[@]}"
}

print_repo_coverage_summary() {
  log_step "Repository coverage"
  collect_discovered_repos
  if (( ${#DISCOVERED_REPOS[@]} == 0 )); then
    log_warn "No repositories discovered in ${FUE_REPO_DIR}"
  else
    log_info "Discovered repositories: ${#DISCOVERED_REPOS[@]}"
    telemetry_set repos_discovered "${#DISCOVERED_REPOS[@]}"
    if [[ "${FUE_SHOW_REPO_LIST:-1}" == "1" ]]; then
      local repo
      for repo in "${DISCOVERED_REPOS[@]}"; do
        log_info "Repo: ${repo}"
      done
    fi
  fi
  if (( ${#FAILED_REPOS[@]} > 0 )); then
    log_warn "Repo failures: ${FAILED_REPOS[*]}"
    telemetry_set repos_failed "${#FAILED_REPOS[@]}"
  fi
  if (( ${#DISABLED_REPOS[@]} > 0 )); then
    log_warn "Temporary fallbacks (disabled): ${DISABLED_REPOS[*]}"
    telemetry_set repos_disabled "${#DISABLED_REPOS[@]}"
  else
    log_ok "No repo fallbacks were required"
  fi
  if (( REPO_ROLLBACK_APPLIED == 1 )); then
    log_warn "Repo-file tuning was rolled back due to retrieval failures"
    telemetry_set repo_rollback applied
  fi
  hr
}

# Parallel-tune repo files (mirrorlist preference + skip_if_unavailable).
tune_repo_files() {
  local jobs="$1" skip="$2"
  if [[ ! -d "$FUE_REPO_DIR" ]]; then
    log_warn "Repo directory not found: $FUE_REPO_DIR"
    return 0
  fi
  snapshot_repo_files
  shopt -s nullglob
  local -a results=()
  local active=0 result_file repo rc c e
  for repo in "$FUE_REPO_DIR"/*.repo; do
    result_file="$(mktemp)"
    results+=("$result_file")
    (
      c=0; e=0
      prefer_mirrorlist_in_repo "$repo"; rc=$?
      [[ "$rc" -eq 0 ]] && c=1
      [[ "$rc" -eq 2 ]] && e=1
      set_skip_if_unavailable_in_repo "$repo" "$skip"; rc=$?
      [[ "$rc" -eq 0 ]] && c=1
      [[ "$rc" -eq 2 ]] && e=1
      echo "${c}:${e}" > "$result_file"
    ) &
    active=$((active + 1))
    if (( active >= jobs )); then
      wait -n || true
      active=$((active - 1))
    fi
  done
  while (( active > 0 )); do
    wait -n || true
    active=$((active - 1))
  done

  local changed=0 errors=0
  for result_file in "${results[@]}"; do
    if [[ -f "$result_file" ]]; then
      IFS=':' read -r c e < "$result_file" || true
      [[ "${c:-0}" == "1" ]] && changed=1
      [[ "${e:-0}" == "1" ]] && errors=1
    fi
    rm -f "$result_file"
  done
  shopt -u nullglob

  if [[ "$changed" -eq 1 ]]; then
    REPO_FILES_MODIFIED=1
    log_ok "Mirrorlist/metalink preferred and repo failover tuned"
  else
    log_info "No mirrorlist/metalink adjustments needed"
  fi
  [[ "$errors" -eq 1 ]] && log_warn "One or more repo files failed safety validation"
}
