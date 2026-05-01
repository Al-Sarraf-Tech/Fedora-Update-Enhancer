# ADR 0007: BATS Test Harness

## Status
Accepted (2026-05-01)

## Context
v1.x had no test suite. CI ran `bash -n` and shellcheck only.
A literal `echo 'Lint-only repo — no test suite'` was the entire `test`
job. There was no way to refactor with confidence, no way to assert
output stability across releases, and no way to test repo-file
mutation logic without a live Fedora host.

## Decision
Adopt `bats-core` (Fedora package: `bats`, version 1.x) for the test
suite. Three test directories:

| Directory               | Purpose                                              |
|-------------------------|------------------------------------------------------|
| `tests/unit/`           | Pure-helper tests; no external commands              |
| `tests/integration/`    | Whole-orchestrator runs against a mock dnf            |
| `tests/golden/`         | Output-stability baselines (help, version)           |

`tests/helper.bash` provides shared setup (`setup_bats_env`,
`source_lib`, `make_fake_dnf`). `tests/mocks/dnf5` is a
shell-script mock that records args + returns canned responses.

Two BATS-specific accommodations were necessary:
1. **Bash assoc arrays don't survive subshells** — each `@test` runs in
   a subshell that does not inherit `declare -A` state. Replaced level
   numbering and telemetry with case-statements + tab-separated file storage.
2. **`set -e` semantics inside tests** — BATS treats any non-zero return
   as test failure. Tests that intentionally exercise non-zero return
   paths use `run` to capture status.

## Consequences
**Positive**
- 45 unit tests + 6 integration tests cover core behavior.
- Refactors are safe — green tests prove no regression.
- New contributors learn the design via the test names, not just the docs.

**Negative**
- BATS adds a runtime dependency (`bats` package). Acceptable; common in
  Fedora CI rigs.
- Subshell quirks documented above must be respected when adding state.
