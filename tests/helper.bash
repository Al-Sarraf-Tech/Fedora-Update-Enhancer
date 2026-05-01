# tests/helper.bash — shared bats setup.

setup_bats_env() {
  PROJECT_ROOT="$(cd -P "${BATS_TEST_DIRNAME}/../.." && pwd)"
  if [[ "${BATS_TEST_DIRNAME}" == */tests ]]; then
    PROJECT_ROOT="$(cd -P "${BATS_TEST_DIRNAME}/.." && pwd)"
  fi
  export FUE_PROJECT_ROOT="$PROJECT_ROOT"
  export FUE_LIB_DIR="${PROJECT_ROOT}/lib"
  export FUE_LOG_FILE_ENABLED=0
  export FUE_LOG_JOURNALD=0
  export FUE_LOG_LEVEL=info

  TMPHOME="$(mktemp -d /tmp/fue-test.XXXXXX)"
  export TMPHOME
}

teardown_bats_env() {
  if [[ -n "${TMPHOME:-}" && -d "${TMPHOME}" ]]; then
    rm -rf "$TMPHOME"
  fi
}

# Source a single library file.
source_lib() {
  local name="$1"
  # shellcheck disable=SC1090
  source "${FUE_LIB_DIR}/${name}.sh"
}

# Build a fake dnf5 binary at $1 that echoes the args it receives.
make_fake_dnf() {
  local path="$1"
  cat >"$path" <<'EOF'
#!/usr/bin/env bash
echo "FAKE_DNF $*" >> "${FAKE_DNF_LOG:-/tmp/fake-dnf.log}"
case "$1" in
  --version) echo "fake-dnf 0.0.0" ;;
  upgrade|update|autoremove|remove|clean|makecache) exit 0 ;;
  repoquery)
    if [[ "$2" == "--installonly" || "$2" == "installonly" ]]; then
      exit 0  # no installonly packages
    fi
    ;;
  history)
    if [[ "$2" == "list" ]]; then
      printf 'ID         | ...\n-----------\n42 | upgrade | ...\n'
    fi
    ;;
esac
exit 0
EOF
  chmod 0755 "$path"
}
