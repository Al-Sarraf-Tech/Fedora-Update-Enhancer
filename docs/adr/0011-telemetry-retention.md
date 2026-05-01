# ADR 0011: Telemetry Retention Policy

## Status
Accepted (2026-05-01)

## Context
Every `elegant-updater` run writes three files to `FUE_LOG_DIR`
(default `/var/log/elegant-updater/`):

- `run-<run_id>.log`   — text log (always; ISO timestamps + level)
- `run-<run_id>.json`  — telemetry (assembled in the EXIT trap)
- `run-<run_id>.kv`    — intermediate kv store (subshell-safe append
  log; deduped + collapsed into the JSON above on `telemetry_flush`)

A run produces typically 10-30 KB across the three files. On a host
running `update` nightly via timer, that's ~30 KB/day, ~11 MB/year.
Across a fleet of hundreds of hosts the per-host volume is fine; the
question is *how long do we keep it locally*?

Three pressures pull in different directions:

1. **Forensics**: an operator hit by a bad upgrade two weeks ago wants
   the telemetry from that run.
2. **Disk**: `/var` is often a small partition; we cannot grow
   unbounded.
3. **Privacy / compliance**: telemetry includes hostname, kernel
   version, fedora version, repo names. None of it is PII or secrets,
   but it's still host-identifying and shouldn't sit forever on a
   shared host.

We also need to decide whether the script itself should rotate, or
delegate to systemd / logrotate.

## Decision

**No rotation built into `elegant-updater`. Default retention is
'never delete; expect the operator to wire systemd-tmpfiles or
logrotate.'**

Documented retention guidance — operators choose one of:

### Option A: systemd-tmpfiles (recommended)

Drop a file at `/etc/tmpfiles.d/elegant-updater.conf`:

```
# Keep elegant-updater telemetry/log for 90 days, then expire.
e /var/log/elegant-updater 0750 root root 90d
```

`systemd-tmpfiles --clean` (run hourly by `systemd-tmpfiles-clean.timer`)
expires anything in `/var/log/elegant-updater/` older than 90 days.

### Option B: logrotate

Drop `/etc/logrotate.d/elegant-updater`:

```
/var/log/elegant-updater/*.log
/var/log/elegant-updater/*.json
/var/log/elegant-updater/*.kv {
    weekly
    rotate 13
    compress
    missingok
    notifempty
    olddir /var/log/elegant-updater/archive
    create 0640 root root
}
```

13 weekly rotations = ~3 months. Compresses old runs.

### Option C: ship and delete

For fleets with a central log/metric store (Loki, journald-remote,
Vector), aggregate first then delete locally:

```
# Shipped via systemd-journald (already on by default — telemetry also
# lives in journald via systemd-cat). Local files become a cache.
e /var/log/elegant-updater 0750 root root 7d
```

7-day local cache, journald is the long-term store.

## Alternatives considered

- **Built-in rotation in `elegant-updater`** — keep N most-recent runs.
  Rejected because rotation in a shell script would mean either:
  (a) a per-run `find -mtime +N -delete` (race-y across overlapping
  runs, even with our flock — the cleanup happens after lock release),
  or (b) a separate `--rotate` flag the operator must wire to a
  timer (we'd be re-implementing logrotate worse).
- **ulimit-style hard cap (e.g. 100 most recent runs)** — same
  objection plus the cap is wrong-shaped (a high-frequency host
  blows 100 runs in days; a quarterly-update host loses years of
  history). Time-based retention is the right axis.
- **Write to journald only, no files** — loses post-mortem grep-ability
  on a host where journald has been tampered with or rotated by a
  different policy.
- **Store in sqlite** — overkill for one-shot CLI telemetry. The
  current append-then-collapse model is JSON-debuggable with `jq`
  and survives SIGKILL (the `.kv` intermediate captures partial
  state).

## Consequences

- **Positive**: Zero new dependencies. Operators with existing
  log-rotation conventions just plug in their preferred mechanism.
- **Positive**: Default behavior (no rotation) is predictable. A
  scheduled `update` for years on the same host produces a
  bounded-rate growth (~30 KB/day) that any sane sysadmin will
  notice within months.
- **Positive**: The three-file scheme (`.log` + `.json` + `.kv`) is
  rotated together by both Option A and Option B because they share
  the same directory and naming pattern.
- **Negative**: Out-of-the-box, a host that runs `update` nightly for
  30 years would accumulate ~330 MB. Documented in README and in this
  ADR; not a bug.
- **Negative**: No retention test exists in the BATS suite — testing
  rotation would require either mocking systemd-tmpfiles or running
  it with `--clean --root=...`. Out of scope.
- **Negative**: Operators who don't read the docs may not configure
  rotation at all. Mitigation: add an explicit hint in
  `docs/RUNBOOKS.md` under R-5 (telemetry sink unreachable) — disk
  full caused by unbounded telemetry is a recoverable case.
