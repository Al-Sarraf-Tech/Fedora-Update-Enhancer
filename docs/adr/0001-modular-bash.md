# ADR 0001: Modular Bash Architecture

## Status
Accepted (2026-05-01)

## Context
The original `elegant-updater.sh` was a single 696-line file mixing concerns
(I/O, dnf orchestration, repo manipulation, sizing, colored output). It was
shellcheck-clean and worked, but every change risked perturbing unrelated
behavior, and there was no way to unit-test individual helpers without
sourcing the whole script (which executes side effects).

## Decision
Split the codebase into a thin orchestrator (`bin/elegant-updater.sh`) plus
single-purpose libraries under `lib/`:

| Module           | Responsibility                                         |
|------------------|--------------------------------------------------------|
| `lib/core.sh`    | Pure helpers: clamp, parse, run-id (no I/O)            |
| `lib/log.sh`     | Logging (text + JSON), journald, telemetry            |
| `lib/system.sh`  | Host detection (Fedora version, CPU, link speed)       |
| `lib/lock.sh`    | flock-based concurrency control                        |
| `lib/preflight.sh` | Disk, RPM-DB lock, network, root checks              |
| `lib/postflight.sh`| Reboot detection, summary                            |
| `lib/dnf.sh`     | dnf operations: config, upgrade, cleanup               |
| `lib/repo.sh`    | repo-file mutation + fallback wrapper                  |

Each module:
- has a double-source guard (`__FUE_X_LOADED__`)
- depends only on previously-loaded modules
- exposes its API via plain functions (no globals leaked except namespaced `FUE_*`)

## Consequences
**Positive**
- Each module is independently testable (BATS unit tests per module).
- Failure modes are localized — a bug in repo logic cannot trash logging.
- The orchestrator (`bin/elegant-updater.sh`) reads top-to-bottom as a flow
  diagram, with implementation details delegated to libs.

**Negative**
- Sourcing chain has a cost (~10ms startup); negligible for an updater.
- Debugging now spans multiple files; mitigated by namespaced globals.

## Alternatives Considered
- **Single file**: rejected — testability and review cost don't scale.
- **Rewrite in Go/Rust**: rejected — bash matches the operational domain
  (composing dnf + system tools); a binary adds packaging burden for no
  meaningful gain.
