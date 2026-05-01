# ADR 0005: First-Class Dry-Run Mode

## Status
Accepted (2026-05-01)

## Context
v1.x had no way to preview what an `update` invocation would do without
actually running it. Operators verifying a change to environment variables
or repo state had to cross fingers and watch.

## Decision
`--dry-run` runs everything *up to* the first mutation and exits 0:

1. Parse args, source libs, validate Fedora version
2. Compute sizing (workers, parallel downloads)
3. Print banner + diagnostic header
4. Acquire lock
5. Run pre-flight (root, dnf-present, disk, rpm-lock, network)
6. Print the planned mutations as `Would: ...` lines
7. Exit 0 — never touches `/etc/dnf/`, repo files, or runs `dnf upgrade`

Activate via `--dry-run` flag or `FUE_DRY_RUN=1` env var.

## Consequences
**Positive**
- CI can run dry-run as a smoke test (catches missing dnf, missing
  /etc/dnf, broken repo files, lock contention) without altering state.
- Operators can verify the computed worker / parallelism values for a
  given host before committing.

**Negative**
- A new code path to maintain. Mitigated by integration tests that
  exercise both modes.
