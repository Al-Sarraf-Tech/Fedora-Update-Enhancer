#!/usr/bin/env bats
# tests/unit/repo.bats — repo file mutation logic.

load "../helper"

setup() {
  setup_bats_env
  source_lib core
  source_lib log
  source_lib dnf
  source_lib repo
  export FUE_REPO_DIR="${TMPHOME}/repos"
  mkdir -p "$FUE_REPO_DIR"
}
teardown() { teardown_bats_env; }

write_repo() {
  local name="$1"; shift
  printf '%s\n' "$@" > "${FUE_REPO_DIR}/${name}.repo"
}

@test "prefer_mirrorlist comments baseurl when metalink present" {
  write_repo demo \
    "[demo]" \
    "name=demo" \
    "baseurl=https://example.com/repo" \
    "metalink=https://example.com/metalink" \
    "enabled=1"
  run prefer_mirrorlist_in_repo "${FUE_REPO_DIR}/demo.repo"
  [ "$status" -eq 0 ]
  grep -q '^#baseurl=' "${FUE_REPO_DIR}/demo.repo"
  grep -q '^metalink=' "${FUE_REPO_DIR}/demo.repo"
}

@test "prefer_mirrorlist leaves baseurl-only repos untouched" {
  write_repo plain \
    "[plain]" \
    "name=plain" \
    "baseurl=https://example.com/repo" \
    "enabled=1"
  run prefer_mirrorlist_in_repo "${FUE_REPO_DIR}/plain.repo"
  [ "$status" -eq 1 ]   # 1 = no change
  grep -q '^baseurl=' "${FUE_REPO_DIR}/plain.repo"
}

@test "set_skip_if_unavailable_in_repo writes True when skip=1" {
  write_repo demo \
    "[demo]" \
    "name=demo" \
    "metalink=https://example.com/metalink" \
    "enabled=1"
  set_skip_if_unavailable_in_repo "${FUE_REPO_DIR}/demo.repo" 1
  grep -q '^skip_if_unavailable=True$' "${FUE_REPO_DIR}/demo.repo"
}

@test "snapshot + restore preserves original" {
  write_repo demo "[demo]" "metalink=https://x" "enabled=1"
  snapshot_repo_files
  echo "[mutated]" > "${FUE_REPO_DIR}/demo.repo"
  restore_repo_backups
  grep -q '^\[demo\]' "${FUE_REPO_DIR}/demo.repo"
}

@test "collect_discovered_repos lists names" {
  write_repo a "[fedora]" "name=fedora"
  write_repo b "[updates]" "name=updates"
  collect_discovered_repos
  [ "${#DISCOVERED_REPOS[@]}" -eq 2 ]
  string_in_array fedora "${DISCOVERED_REPOS[@]}"
  string_in_array updates "${DISCOVERED_REPOS[@]}"
}

@test "extract_failed_repos pulls names from log" {
  log_file="${TMPHOME}/dnf-error.log"
  cat >"$log_file" <<'EOF'
Failed to download metadata for repo 'rpmfusion-free'
Error: All mirrors were tried for repo 'docker-ce'
EOF
  result="$(extract_failed_repos "$log_file" | sort)"
  expected="$(printf 'docker-ce\nrpmfusion-free' | sort)"
  [ "$result" = "$expected" ]
}

@test "validate_repo_candidate accepts well-formed file" {
  write_repo good "[good]" "name=good"
  validate_repo_candidate "${FUE_REPO_DIR}/good.repo"
}

@test "validate_repo_candidate rejects empty section-less file" {
  echo "no sections here" > "${FUE_REPO_DIR}/bad.repo"
  ! validate_repo_candidate "${FUE_REPO_DIR}/bad.repo"
}
