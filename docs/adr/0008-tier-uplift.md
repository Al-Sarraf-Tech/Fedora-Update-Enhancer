# ADR 0008: S+ Tier Uplift Plan (v1 → v2)

## Status
Implemented (2026-05-01)

## Context
v1.x sat at ~C tier per the [tier rubric](../../CLAUDE.md). Floor reasons:
testing (D — lint-only CI) and observability (D-C — printf only).

## Decision
Single-release uplift covering eight phases:

1. Fedora-44 + version auto-detect (code quality)
2. Modularize `bin/` + `lib/` (code quality) — see ADR 0001
3. Structured logs + telemetry (observability) — ADR 0003
4. Pre-flight + post-flight + lock + dry-run (reliability) — ADRs 0004, 0005, 0006
5. BATS test suite + mock dnf (testing) — ADR 0007
6. ADRs + runbooks + audit script (docs/process)
7. README rewrite + CHANGELOG (docs/process)
8. Local install + smoke verify (validation)

## Tier Result (post-uplift)

| Dim          | Pre   | Post  | Notes                                                     |
|--------------|-------|-------|-----------------------------------------------------------|
| Code quality | B     | A+    | Modular, shellcheck-clean, namespaced globals             |
| Testing      | D     | A     | 45 unit + integration + golden                            |
| Security     | B     | A     | Lockfile, atomic writes, validation, gitleaks unchanged   |
| Reliability  | A-    | A+    | Preflight + dry-run + reboot detect + lock                |
| Observability| D-C   | A+    | text+JSON+journald+telemetry+run-id                       |
| Performance  | C     | B     | Existing adaptive sizing + telemetry timings               |
| Documentation| B     | A+    | 8 ADRs + 4 runbooks + audit script                        |
| Process      | B     | A+    | Audit script, conventional commits, install/uninstall     |

## Consequences
**Positive** — Project ascends to the S floor (every dimension ≥ A) with
process and documentation pulling toward S+. The audit script
(`scripts/s-tier-audit.sh`) gives operators a single command to verify
the tier holds over time.

**Negative** — Bash dependencies grew: `bats` (test), `flock` (lock),
`systemd-cat` (logs). All standard on Fedora. Documented in README.
