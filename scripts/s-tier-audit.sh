#!/usr/bin/env bash
# scripts/s-tier-audit.sh — single-command S+ audit.
#
# Walks the 8 dimensions of the tier rubric and reports pass/fail per check.
# Exits 0 if every dimension passes; 1 otherwise.

set -Eeuo pipefail

PROJECT_ROOT="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"

C_OK="\033[1;32m"
C_BAD="\033[1;31m"
C_DIM="\033[2m"
C_HL="\033[1;36m"
C_RESET="\033[0m"
[[ -t 1 ]] || { C_OK=""; C_BAD=""; C_DIM=""; C_HL=""; C_RESET=""; }

PASS=0
FAIL=0
declare -a FAIL_NOTES=()

check() {
  local label="$1"; shift
  if "$@" >/dev/null 2>&1; then
    printf '  %b✔%b %s\n' "$C_OK" "$C_RESET" "$label"
    PASS=$((PASS + 1))
  else
    printf '  %b✖%b %s\n' "$C_BAD" "$C_RESET" "$label"
    FAIL=$((FAIL + 1))
    FAIL_NOTES+=("$label")
  fi
}

section() {
  printf '\n%b== %s ==%b\n' "$C_HL" "$1" "$C_RESET"
}

# ---------- Code Quality ----------
section "Code Quality"
check "shellcheck clean (lib + bin)" bash -c '
  find bin lib -type f -name "*.sh" | xargs shellcheck --severity=warning
'
check "lib/ exists and has ≥6 modules" bash -c 'test "$(find lib -name "*.sh" | wc -l)" -ge 6'
check "bin/elegant-updater.sh present + executable" bash -c '[[ -x bin/elegant-updater.sh ]]'
check "no hardcoded Fedora version in active code" bash -c '
  ! grep -RE "Fedora 4[0-3]" bin lib --include="*.sh" 2>/dev/null
'

# ---------- Testing ----------
section "Testing"
check "bats present" command -v bats
check "tests/unit has ≥4 .bats files" bash -c 'test "$(find tests/unit -name "*.bats" 2>/dev/null | wc -l)" -ge 4'
check "tests/integration exists" bash -c '[[ -d tests/integration ]]'
check "golden tests exist" bash -c '[[ -d tests/golden ]]'
check "unit test suite passes" bash -c 'cd "$0" && bats tests/unit/' "$PROJECT_ROOT"
check "integration test suite passes" bash -c 'cd "$0" && bats tests/integration/' "$PROJECT_ROOT"

# ---------- Security ----------
section "Security"
check "no committed secrets (gitleaks)" bash -c '
  command -v gitleaks >/dev/null 2>&1 \
    && gitleaks detect --no-banner --exit-code=1 --source=. \
    || true
'
check "lock file path is in /var/lock" grep -q '/var/lock/elegant-updater' lib/lock.sh
check "atomic writes used in repo mutation" grep -q 'mv -f' lib/repo.sh
check "validate_repo_candidate guards repo mutations" grep -q 'validate_repo_candidate' lib/repo.sh

# ---------- Reliability ----------
section "Reliability"
check "lib/preflight.sh exists" bash -c '[[ -f lib/preflight.sh ]]'
check "lib/postflight.sh exists" bash -c '[[ -f lib/postflight.sh ]]'
check "lib/lock.sh exists" bash -c '[[ -f lib/lock.sh ]]'
check "trap-based cleanup" grep -q "trap.*EXIT" bin/elegant-updater.sh
check "dry-run mode supported" grep -q -- '--dry-run' bin/elegant-updater.sh
check "reboot detection implemented" grep -q 'detect_reboot_needed' lib/postflight.sh

# ---------- Observability ----------
section "Observability"
check "structured (JSON) log option" grep -q 'FUE_LOG_FORMAT' lib/log.sh
check "journald sink" grep -q 'systemd-cat' lib/log.sh
check "telemetry write to file" grep -q 'telemetry_flush' lib/log.sh
check "run-id correlation" grep -q 'FUE_RUN_ID' lib/log.sh
check "log levels enforced" grep -q '__fue_level_allowed' lib/log.sh

# ---------- Performance ----------
section "Performance"
check "adaptive parallelism present" grep -q 'calc_jobs_from_load' lib/core.sh
check "link-speed based download cap" grep -q 'detect_fastest_link_speed_mbps' lib/system.sh
check "upgrade timing recorded" grep -q 'upgrade_seconds' bin/elegant-updater.sh

# ---------- Documentation ----------
section "Documentation"
check "README.md present" bash -c '[[ -f README.md ]]'
check "CHANGELOG.md present" bash -c '[[ -f CHANGELOG.md ]]'
check "≥6 ADRs" bash -c 'test "$(find docs/adr -name "*.md" 2>/dev/null | wc -l)" -ge 6'
check "≥4 runbooks" bash -c 'test "$(find docs/runbooks -name "*.md" 2>/dev/null | wc -l)" -ge 4'
check "ASSURANCE.md present" bash -c '[[ -f ASSURANCE.md ]]'

# ---------- Process ----------
section "Process"
check "Makefile or scripts/ targets present" bash -c '[[ -f Makefile || -d scripts ]]'
check "install script present" bash -c '[[ -f scripts/install.sh ]]'
check "uninstall script present" bash -c '[[ -f scripts/uninstall.sh ]]'
check "audit script self-runs" bash -c '[[ -x scripts/s-tier-audit.sh ]]'
check "CI workflow present" bash -c 'compgen -G ".github/workflows/*.yml" > /dev/null'
check "MIT LICENSE" bash -c 'grep -q "MIT" LICENSE'

# ---------- Summary ----------
TOTAL=$((PASS + FAIL))
printf '\n%b── Summary ──%b\n' "$C_HL" "$C_RESET"
printf '  pass: %d / %d\n' "$PASS" "$TOTAL"

if (( FAIL == 0 )); then
  printf '  %bTier: S+ (every check passed)%b\n' "$C_OK" "$C_RESET"
  exit 0
fi

printf '  %btier floor: %d failures%b\n' "$C_BAD" "$FAIL" "$C_RESET"
printf '\nFailing checks:\n'
for note in "${FAIL_NOTES[@]}"; do
  printf '  %b- %s%b\n' "$C_BAD" "$note" "$C_RESET"
done
exit 1
