# Changelog

All notable changes to this project are documented in this file. Format
follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the
project adheres to [Semantic Versioning](https://semver.org/).

## [2.0.0] - 2026-05-01

### Added
- Modular architecture: `bin/elegant-updater.sh` orchestrator + 8
  single-purpose libraries under `lib/` (see ADR 0001).
- Auto-detection of Fedora release via `/etc/os-release` — banner and
  validation now reflect the running host (ADR 0002). Fedora 44 supported.
- Structured logging:
  - text or JSON output (`--json` / `FUE_LOG_FORMAT`),
  - journald sink (`systemd-cat`, on by default),
  - per-run log file at `/var/log/elegant-updater/run-<id>.log`,
  - per-run telemetry JSON sibling file (ADR 0003).
- Concurrency control via `flock` on `/var/lock/elegant-updater.lock`;
  exits 11 on contention (ADR 0004).
- `--dry-run` mode: prints the plan without mutating system state (ADR 0005).
- Pre-flight checks: root, dnf binary, `/var` and `/boot` free space,
  rpm-DB lock contention, network reachability (ADR 0006).
- Post-flight: reboot-needed detection, last-transaction id capture.
- BATS test suite: 45 unit tests + 6 integration + 2 golden tests, with
  a mock `dnf5` binary for offline integration testing (ADR 0007).
- 8 Architecture Decision Records (`docs/adr/`).
- 4 Runbooks for the most common failure modes (`docs/runbooks/`).
- `scripts/s-tier-audit.sh` — single-command rubric audit.
- `scripts/install.sh` and `scripts/uninstall.sh` — atomic, FHS-compliant
  install at `/usr/local/lib/elegant-updater/`, with `update` and
  `elegant-updater` symlinks in `/usr/local/bin/`.
- `Makefile` with `test`, `lint`, `audit`, `install`, `uninstall`, and
  `dry-run` targets.
- New CLI flags: `--version`, `--help`, `--debug`, `--quiet`,
  `--no-banner`, `--no-journald`, `--audit`, `--uninstall`.

### Changed
- Project layout: scripts that lived at the repo root now sit under
  `bin/` and `lib/`. The legacy `elegant-updater.sh` at the repo root is
  retained as a compatibility shim (deprecated; remove in 3.0.0).
- The banner subtitle is built from `/etc/os-release` instead of being
  hardcoded.
- Default log destination: `/var/log/elegant-updater/run-<id>.log`
  (previously stdout-only).
- Adaptive sizing logic moved to `lib/core.sh` and `lib/system.sh`;
  algorithm unchanged.
- Repo mutation logic moved to `lib/repo.sh`; algorithm unchanged.

### Migration Notes
- All v1.x environment variables (`MAX_PARALLEL_DOWNLOADS`, `JOBS`,
  `PREFER_MIRRORS`, etc.) continue to work unchanged.
- Operators with prior shell aliases pointing at
  `/usr/local/bin/update` need no changes; the install script keeps the
  symlink target identical.
- New variables introduced; defaults preserve v1.x behavior:
  - `FUE_LOG_FORMAT=text` (default; set `json` for structured logs)
  - `FUE_LOG_DIR=/var/log/elegant-updater`
  - `FUE_LOG_JOURNALD=1`
  - `FUE_PREFLIGHT_FATAL=1`
  - `FUE_MIN_FREE_VAR_MB=2048`, `FUE_MIN_FREE_BOOT_MB=256`

## [1.0.1] - 2026-04-08

### Added
- CI/CD pipeline with `repo-guard`, lint, test, security, sbom, integration,
  release jobs.
- ASSURANCE.md documenting CI gates and supply-chain controls.

## [1.0.0] - 2026-03-03

### Added
- Initial release. Single-file `elegant-updater.sh` with adaptive
  parallelism, repo mirror failover, and dnf5 tuning.

[2.0.0]: https://github.com/Al-Sarraf-Tech/Fedora-Update-Enhancer/releases/tag/v2.0.0
[1.0.1]: https://github.com/Al-Sarraf-Tech/Fedora-Update-Enhancer/releases/tag/v1.0.1
[1.0.0]: https://github.com/Al-Sarraf-Tech/Fedora-Update-Enhancer/releases/tag/v1.0.0
