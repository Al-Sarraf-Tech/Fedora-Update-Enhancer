# ADR 0004: flock-based Concurrency Control

## Status
Accepted (2026-05-01)

## Context
Two concurrent invocations would race on `/etc/dnf/dnf.conf`, `*.repo`
file mutations, and the rpm database. v1.x had no defense — only dnf's
own rpm-DB lock, which is held mid-transaction but not during config
mutation.

## Decision
Acquire an exclusive `flock` on `/var/lock/elegant-updater.lock` at
startup, before any preflight or mutation. Release on EXIT trap.

Behavior:
- `flock -n` (non-blocking by default) → exit 11 immediately if another
  run is in progress.
- `acquire_lock <timeout>` for callers who want to wait.
- `flock` not present → log a warning and continue (gracefully degraded,
  Bash containers may not have util-linux).
- Lock file world-readable; PID + timestamp written for diagnostics.

## Consequences
**Positive**
- Two concurrent `update` invocations cannot corrupt config.
- Operator running update via cron + ssh-tickle simultaneously is safe.
- Distinct exit code (11) lets callers retry.

**Negative**
- Lock file persists between runs (zero-byte). Acceptable.
- A killed process leaves the file but flock auto-releases on FD close.
