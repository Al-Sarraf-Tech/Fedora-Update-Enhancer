#!/usr/bin/env bats
# tests/unit/system.bats — system detection.

load "../helper"

setup() {
  setup_bats_env
  source_lib core
  source_lib system
  cat >"${TMPHOME}/os-release-fedora44" <<'EOF'
NAME="Fedora Linux"
VERSION="44 (Cinnamon)"
ID=fedora
VERSION_ID=44
PRETTY_NAME="Fedora Linux 44 (Cinnamon)"
EOF
  cat >"${TMPHOME}/os-release-debian" <<'EOF'
NAME="Debian GNU/Linux"
VERSION="12 (bookworm)"
ID=debian
VERSION_ID="12"
PRETTY_NAME="Debian GNU/Linux 12 (bookworm)"
EOF
}
teardown() { teardown_bats_env; }

@test "__fue_os_release_value parses ID from fedora44" {
  result="$(__fue_os_release_value ID "${TMPHOME}/os-release-fedora44")"
  [ "$result" = "fedora" ]
}

@test "__fue_os_release_value strips quotes" {
  result="$(__fue_os_release_value VERSION_ID "${TMPHOME}/os-release-debian")"
  [ "$result" = "12" ]
}

@test "__fue_os_release_value missing key yields empty" {
  result="$(__fue_os_release_value NOTAKEY "${TMPHOME}/os-release-fedora44")"
  [ -z "$result" ]
}

@test "build_banner_subtitle on Fedora 44 produces version" {
  cp "${TMPHOME}/os-release-fedora44" "${TMPHOME}/etc-os-release"
  detect_fedora_id() { echo fedora; }
  detect_fedora_version() { echo 44; }
  detect_fedora_pretty() { echo "Fedora Linux 44 (Cinnamon)"; }
  result="$(build_banner_subtitle)"
  [ "$result" = "Fedora 44 Update" ]
}

@test "build_banner_subtitle on non-Fedora uses pretty name" {
  detect_fedora_id() { echo debian; }
  detect_fedora_version() { echo 12; }
  detect_fedora_pretty() { echo "Debian GNU/Linux 12 (bookworm)"; }
  result="$(build_banner_subtitle)"
  [ "$result" = "Debian GNU/Linux 12 (bookworm) Update" ]
}

@test "validate_fedora_supported: fedora 44 → 0" {
  detect_fedora_id() { echo fedora; }
  detect_fedora_version() { echo 44; }
  validate_fedora_supported
  [ $? -eq 0 ]
}

@test "validate_fedora_supported: fedora 41 → 1 (warn)" {
  detect_fedora_id() { echo fedora; }
  detect_fedora_version() { echo 41; }
  set +e
  validate_fedora_supported
  rc=$?
  set -e
  [ "$rc" -eq 1 ]
}

@test "validate_fedora_supported: non-fedora → 2" {
  detect_fedora_id() { echo debian; }
  detect_fedora_version() { echo 12; }
  set +e
  validate_fedora_supported
  rc=$?
  set -e
  [ "$rc" -eq 2 ]
}

@test "detect_cpu_cores returns positive integer" {
  result="$(detect_cpu_cores)"
  [[ "$result" =~ ^[0-9]+$ ]]
  (( result > 0 ))
}
