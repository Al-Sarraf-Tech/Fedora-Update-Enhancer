# ADR 0006: Pre-flight and Post-flight Checks

## Status
Accepted (2026-05-01)

## Context
v1.x ran `dnf5 upgrade` regardless of host state. Common failure modes
were diagnosable only after a partial transaction:
- `/var` full (incomplete download / orphaned RPMs)
- another dnf or PackageKit holding the rpm DB
- network unreachable (would surface as repo failures mid-transaction)

## Decision
**Pre-flight** runs before any mutation:

| Check                    | Default        | Override                             |
|--------------------------|----------------|--------------------------------------|
| Running as root          | required       | n/a                                  |
| dnf binary present       | required       | `FUE_DNF`                            |
| `/var` free ≥ 2048 MB    | required       | `FUE_MIN_FREE_VAR_MB`                |
| `/boot` free ≥ 256 MB    | required       | `FUE_MIN_FREE_BOOT_MB`               |
| rpm DB unlocked          | required       | `FUE_ALLOW_PACKAGEKIT=1`             |
| network reachable        | warning only   | `FUE_PREFLIGHT_NETWORK=0`            |

Failure semantics: `FUE_PREFLIGHT_FATAL=1` (default) aborts; `=0` warns
and continues (useful for offline test rigs).

**Post-flight** runs after upgrade completes:
- Detect reboot-needed (via `dnf needs-restarting --reboothint`, falls
  back to running-vs-installed kernel comparison).
- Record last transaction id from `dnf history list`.
- Emit telemetry summary.

## Consequences
**Positive**
- Failures surface with diagnostic context, not as opaque dnf errors.
- Disk-full and rpm-DB lock are detected before any download starts.
- Reboot-needed is now a reliable telemetry field, not a manual operator step.

**Negative**
- Network probe to `mirrors.fedoraproject.org` requires DNS+TCP. Operators
  on air-gapped networks set `FUE_PREFLIGHT_NETWORK=0`.
