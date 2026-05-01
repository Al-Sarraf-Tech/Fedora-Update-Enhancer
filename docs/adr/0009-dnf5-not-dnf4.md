# ADR 0009: Target dnf5, not dnf4

## Status
Accepted (2026-05-01)

## Context
Fedora 41 introduced `dnf5` as the default package manager and demoted
`dnf4` (the pre-existing Python implementation, now packaged as
`dnf5-shim` and `python3-dnf` for compatibility). Fedora 44 fully
removes dnf4 from the default install. We had to choose:

1. Target the dnf4 Python codepath via `/usr/bin/dnf` (pre-F41 default).
2. Target dnf5 via `/usr/bin/dnf5` (F41+ default; the libdnf5 C++
   implementation).
3. Auto-detect, branch in code, and support both.

Each option has cost and risk. The relevant constraints:

- All Al-Sarraf-Tech-managed hosts run Fedora 43 or 44.
- Older targets (F40 and below) are out of support per README's
  OS support matrix.
- dnf4 and dnf5 differ in CLI semantics: `--setopt`, `--repo-id`,
  `repoquery` flags, `history` output format, and the
  `needs-restarting --reboothint` exit code semantics.
- dnf5 is faster (libdnf5 + libsolv5; no Python startup), uses ~80%
  less RAM, and is the only path forward — dnf4 is in maintenance,
  not feature, mode.

## Decision

**Target `dnf5` exclusively.** `FUE_DNF` defaults to `/usr/bin/dnf5`
and the orchestrator's pre-flight aborts (exit 1) if `dnf5` is not
found. The OS support matrix in README codifies the same: F41+ only,
F40 and below explicitly unsupported (exit 70 — wrong-OS code).

Where dnf5's CLI surface differs from dnf4's, we use the dnf5 form
unconditionally. The two places where we still feature-detect:

1. `dnf5 makecache --timer` — only some dnf5 builds expose `--timer`.
   `lib/dnf.sh::dnf_makecache` greps `--help` and falls back to plain
   `makecache` if absent. Cheap detection, not version-pinning.
2. `dnf5 repoquery --installonly` vs the older positional form. Same
   pattern.

These are intentionally narrow — every other call site assumes dnf5
semantics.

## Alternatives considered

- **Auto-detect dnf4 + dnf5, branch in code.** Doubles the test
  matrix, breaks the BATS mock (which currently mocks dnf5 only),
  and forces every contributor to know two CLIs. The ROI is
  approximately zero — no in-scope host runs dnf4.
- **Target `/usr/bin/dnf` and let the alternatives system handle it.**
  On F44 the alternative points at `dnf5` anyway, so this is just
  indirection. On older hosts it would silently use dnf4 — we
  *don't* want silent backend swaps in a tool that mutates the
  RPM database.
- **Pin a minimum dnf5 version (`>= 5.4.0`).** Considered. Rejected
  because Fedora's own repos always ship the version that matches
  the release; any host on F43 has dnf5 >= 5.2.x, on F44 >= 5.4.x.
  Pinning would force operators to upgrade dnf5 separately, which
  defeats the point of using the system package manager.

## Consequences

- **Positive**: One CLI surface, one mock, one set of integration
  tests. The orchestrator is ~30 % shorter than the auto-detect
  alternative (estimated from a discarded prototype).
- **Positive**: We get dnf5's perf improvements (libdnf5 + libsolv5)
  for free — typical `upgrade --best` runs are 1.5-2x faster than
  the dnf4 equivalent on the same package set.
- **Positive**: Future libdnf5 features (e.g. plugins, transaction
  hooks) are accessible without a refactor.
- **Negative**: Cannot run on F40 or below. Documented in the OS
  support matrix; pre-flight refuses with a clear error code (70).
- **Negative**: A future dnf6 (no public timeline as of 2026-05) will
  require an analogous decision, not a transparent migration.
  Acceptable — tracked.
