# Service-Level Objectives

Per-operation latency SLOs for `elegant-updater`. Each SLO names the
operation, the target percentile, the measurement source, the alert
threshold (the point at which a regression should be investigated), and
the recovery action expected of the operator.

These SLOs are *latency* objectives, not availability — `elegant-updater`
is a one-shot CLI, not a service. "Availability" maps to exit-code zero
on a clean host (covered by the BATS integration suite, not here).

All numbers assume a single-host run on Fedora 43 or 44 with `dnf5
>= 5.4`, ≥ 4 CPU cores, ≥ 2 GB free in `/var`, and a working network
link.

---

## SLO-1 — dnf metadata refresh

| Field | Value |
|---|---|
| Operation | `dnf_clean_expire_cache` + `dnf5 makecache` (lib/dnf.sh) |
| Target | p99 < **30 s** on cache-hit (metadata fresh, mirrors cached) |
| Target | p99 < **90 s** on cold-cache (first run after `dnf clean all`) |
| Measured by | `scripts/perf-bench.sh metadata-refresh` |
| Telemetry key | `metadata_refresh_seconds` (added to per-run telemetry) |
| Alert if | p99 > 45 s warm or > 135 s cold (1.5x SLO) on baseline-vs-PR |
| Operator action | See `docs/runbooks/network.md` for mirror failover; cache cold-cause root analysis at `journalctl -u dnf-makecache.service` |

**Rationale**: A warm cache only revalidates `repomd.xml` per repo —
~30 repo HEAD requests dominated by RTT. A cold cache pulls every
`primary.xml.gz` and `filelists.xml.gz` — bandwidth-bound at ~25 MB
total per Fedora repo set. Both numbers measured on amarillo over a
1 Gb/s link.

---

## SLO-2 — System upgrade run

| Field | Value |
|---|---|
| Operation | full `bin/elegant-updater.sh` invocation (preflight → upgrade → cleanup → postflight) |
| Target | p99 < **5 min** for typical (~50 packages, no kernel) |
| Target | p99 < **15 min** for kernel-included transactions |
| Measured by | `scripts/perf-bench.sh full-run` (against mock dnf5 — wall-clock minus dnf transaction time) |
| Telemetry key | `upgrade_seconds` (already captured) + `wall_clock_seconds` (added) |
| Alert if | wall-clock minus `upgrade_seconds` > 10 % of total — orchestrator overhead is leaking |
| Operator action | Run `--debug` to see per-phase timings; check telemetry for outlier `repos_failed`, `repos_disabled` |

**Rationale**: Most wall-clock time is `dnf5 upgrade` itself
(network-bound). The orchestrator's own overhead (preflight + repo
tuning + postflight) should stay under ~10 % of that — the SLO
implicitly bounds orchestrator latency, not dnf's.

---

## SLO-3 — Adaptive sizing decision

| Field | Value |
|---|---|
| Operation | `calc_jobs_from_load` + `detect_fastest_link_speed_mbps` + parallel-downloads computation (orchestrator startup) |
| Target | p99 < **100 ms** on any host with `nproc`, `awk`, and `/sys/class/net` |
| Measured by | `scripts/perf-bench.sh sizing-decision` |
| Telemetry key | `sizing_decision_ms` (added) |
| Alert if | p99 > 250 ms — implies an awk fork or `/sys` fs is mis-mounted |
| Operator action | `bash -x bin/elegant-updater.sh --dry-run --no-banner 2>&1 | grep -E '^\+' | head -50` to find the slow primitive |

**Rationale**: Sizing is `nproc` + `cat /proc/loadavg` + ≤ 4 `cat
/sys/class/net/*/speed` + one awk invocation. On a healthy host this
fits well inside 100 ms. A regression here points at a slow `/sys` mount
(NFS, FUSE) or a runaway awk script.

---

## Measurement methodology

`scripts/perf-bench.sh` is the single source of truth. CI runs it on
every PR, compares against the baseline (`tests/baseline-perf.json`),
and fails if any p99 regresses by more than **15 %**.

Local invocation:

```bash
scripts/perf-bench.sh                    # all SLOs, prints JSON
scripts/perf-bench.sh metadata-refresh   # one SLO
PERF_BENCH_RUNS=10 scripts/perf-bench.sh # more samples (default 5)
```

The bench uses the in-tree mock `tests/mocks/dnf5` and a tmp `repos/`
dir to stay hermetic — no network, no real package install. SLO-1 in
particular is a *baseline-only* upper bound (mock returns instantly);
real cold-cache numbers must be measured on a live host with
`PERF_BENCH_NETWORK=1` and are not gated in CI.

## Baseline

The baseline lives at `tests/baseline-perf.json` and is regenerated
manually when an intentional perf change ships:

```bash
PERF_BENCH_RUNS=20 scripts/perf-bench.sh > tests/baseline-perf.json
git add tests/baseline-perf.json
git commit -m "perf: refresh baseline after <change>"
```

The CI gate in `.github/workflows/ci-shell.yml` runs the bench against
this baseline. A 15 % regression on any p99 fails the PR.

## Limitations

- p99 from 5 samples is statistically weak; CI samples 20 with
  `PERF_BENCH_RUNS=20` to compensate.
- The mock dnf5 doesn't simulate IO contention or solver work, so
  SLO-2 wall-clock minus dnf time only captures orchestrator overhead
  growth, not regressions inside dnf5 itself.
- SLO-1 cold-cache numbers depend on Fedora mirror health; treated as
  observational, not a CI gate.
