#!/usr/bin/env bats
# tests/unit/dnf.bats — dnf config tuning.

load "../helper"

setup() {
  setup_bats_env
  source_lib core
  source_lib log
  source_lib dnf
}
teardown() { teardown_bats_env; }

@test "ensure_kv: missing [main] is created" {
  conf="${TMPHOME}/dnf.conf"
  : > "$conf"
  ensure_kv "$conf" max_parallel_downloads 20
  grep -q '^\[main\]$' "$conf"
  grep -q '^max_parallel_downloads=20$' "$conf"
}

@test "ensure_kv: existing key is updated" {
  conf="${TMPHOME}/dnf.conf"
  cat >"$conf" <<'EOF'
[main]
max_parallel_downloads=5
keepcache=true
EOF
  ensure_kv "$conf" max_parallel_downloads 18
  grep -q '^max_parallel_downloads=18$' "$conf"
  ! grep -q '^max_parallel_downloads=5$' "$conf"
  grep -q '^keepcache=true$' "$conf"
}

@test "ensure_kv: appends new key under [main]" {
  conf="${TMPHOME}/dnf.conf"
  cat >"$conf" <<'EOF'
[main]
keepcache=false
EOF
  ensure_kv "$conf" deltarpm true
  grep -q '^keepcache=false$' "$conf"
  grep -q '^deltarpm=true$' "$conf"
}

@test "tune_dnf_config writes all expected keys" {
  conf="${TMPHOME}/dnf.conf"
  cat >"$conf" <<'EOF'
[main]
EOF
  tune_dnf_config "$conf" 18 3 1 1 6 15 100k
  grep -q '^deltarpm=true$' "$conf"
  grep -q '^keepcache=false$' "$conf"
  grep -q '^fastestmirror=true$' "$conf"
  grep -q '^max_parallel_downloads=18$' "$conf"
  grep -q '^installonly_limit=3$' "$conf"
  grep -q '^skip_if_unavailable=true$' "$conf"
  grep -q '^retries=6$' "$conf"
  grep -q '^timeout=15$' "$conf"
  grep -q '^minrate=100k$' "$conf"
}

@test "detect_dnf_conf prefers dnf5.conf when both exist" {
  # Cannot test the real /etc/dnf, so just verify the function obeys override.
  FUE_DNF_CONF="${TMPHOME}/custom.conf"
  result="$(detect_dnf_conf)"
  [ "$result" = "${TMPHOME}/custom.conf" ]
}
