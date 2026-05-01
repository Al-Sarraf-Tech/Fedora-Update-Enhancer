# ADR 0003: Structured Logs and Per-Run Telemetry

## Status
Accepted (2026-05-01)

## Context
v1.x emitted printf-formatted output to stdout only. Operators had no way to:
- aggregate runs across hosts (no JSON)
- correlate a failure to a single run (no run-id)
- retrieve historical state without `tee`-ing manually
- ship to journald/systemd

## Decision
Three concurrent log sinks, all toggleable:

1. **Stdout (text or JSON)** — controlled by `--json` / `FUE_LOG_FORMAT=json`.
   Text format keeps the existing icon prefixes (`✔ ▲ ✖ • ==>`).
2. **Per-run log file** — `FUE_LOG_DIR/run-<run-id>.log` (default
   `/var/log/elegant-updater/`). Always plain text + ISO timestamps for
   later parsing.
3. **journald** — via `systemd-cat -t elegant-updater`, on by default,
   disabled with `--no-journald`.

Plus a per-run telemetry JSON file capturing structured metrics:
`run_id`, `version`, `fedora_version`, `kernel`, `jobs`,
`max_parallel_downloads`, `dry_run`, `started_at`, `finished_at`,
`exit_code`, `upgrade_seconds`, `repos_discovered`, `repos_failed`,
`repos_disabled`, `reboot_needed`, `last_tx_id`.

Telemetry is file-backed (tab-separated kv) so it survives subshell
boundaries, then assembled into JSON on `telemetry_flush`.

## Consequences
**Positive**
- A single run can be reconstructed from its log + telemetry pair.
- Operators can ship telemetry to a metrics pipeline without re-parsing
  human logs.
- journald integration gives free integration with `systemctl status`,
  log retention, and remote shipping.

**Negative**
- A small write-amplification cost per log line (text + file + journald).
  Insignificant for human-paced output.
- Telemetry kv format must be stable across releases (semver-locked at v2.0.0).
