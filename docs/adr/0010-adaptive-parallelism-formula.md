# ADR 0010: Adaptive Parallelism Formula

## Status
Accepted (2026-05-01)

## Context
`elegant-updater` runs two independent parallel workloads:

1. **Repo file mutation** (`tune_repo_files` in `lib/repo.sh`) — N
   independent text rewrites in tmp + atomic mv. CPU-bound but trivial.
2. **dnf parallel downloads** — controlled by
   `max_parallel_downloads` in dnf config and on the CLI. Network-bound
   with a sub-linear scaling profile (mirrors throttle, TLS handshakes
   serialize, libcurl multiplexing helps but caps out around 8-16
   concurrent streams per host).

Both workloads need a parallelism number, but the limits come from
different resources (CPU vs network bandwidth). We needed a formula
that:

- Picks a *single* sensible value for both without operator tuning.
- Adapts to the host (8-core laptop vs 64-core builder).
- Adapts to current load (don't stomp on a busy host).
- Caps at the point where additional concurrency is counterproductive
  (mirror throttling, TCP congestion).
- Is overrideable per env var for operators with measured numbers.

## Decision

Two independent computations, both bounded:

### CPU workers (`JOBS`)

Linear interpolation against current 1m loadavg, clamped to a floor and
ceiling:

```
ratio  = clamp(loadavg_1m / cpu_cores, 0, 1)
JOBS   = max_jobs - (ratio * (max_jobs - min_jobs))
JOBS   = clamp(JOBS, EFFECTIVE_MIN_CPU_WORKERS, EFFECTIVE_MAX_CPU_WORKERS)
```

Defaults: `MIN_CPU_WORKERS=10`, `MAX_CPU_WORKERS=20`. On hosts with
fewer cores than the floor, the effective floor is clamped to
`cpu_cores`.

Implementation: `calc_jobs_from_load` in `lib/core.sh` (an awk
one-shot — pure, no I/O, deterministic).

### Network parallel downloads (`MAX_PARALLEL_DOWNLOADS`)

Three-way minimum, taking the smallest of:

1. **CPU stream limit**: `JOBS * 2` — at most 2 concurrent streams per
   worker process.
2. **Hard cap**: `DNF_PARALLEL_CAP=20` — beyond this, mirror throttling
   dominates regardless of bandwidth (measured against
   mirrors.fedoraproject.org).
3. **Link-bandwidth limit**: `link_speed_mbps / STREAM_MBIT_PER_CONN`
   — assumes each download saturates ~35 Mb/s sustained (defensible
   number for HTTPS rpm fetches over TLS 1.3, measured on amarillo).

Then take 95% of that ceiling (`STREAM_UTILIZATION_PERCENT=95`) so
we leave headroom for retries, kernel scheduling, and other downloads
on the host.

```
theoretical = min(JOBS*2, DNF_PARALLEL_CAP, link_mbps / STREAM_MBIT_PER_CONN)
chosen      = max(1, theoretical * STREAM_UTILIZATION_PERCENT / 100)
chosen      = clamp(chosen, 1, DNF_PARALLEL_CAP)
```

Implementation: inline in `bin/elegant-updater.sh` (the formula uses
multiple already-computed scalars; pulling it into a function would
require either a struct or 8-arg passing).

## Alternatives considered

- **Hardcoded `MAX_PARALLEL_DOWNLOADS=20`** (the dnf default cap).
  Wastes CPU on small hosts (8-core laptop opens 20 sockets that all
  contend), under-uses CPU on big builders.
- **CPU-only sizing (ignore link)**. Easy, but on a 1 Gb/s link with
  64 cores you'd compute 128 streams — every Fedora mirror caps you
  to ~10 concurrent connections per source IP. The extra streams just
  fail and retry.
- **Bandwidth-only sizing (ignore CPU)**. Conversely, on a 10 Gb/s
  link with 4 cores you'd compute ~285 streams — TLS handshakes alone
  would saturate the cores, and dnf's solver runs single-threaded
  while downloads happen, so there's no benefit.
- **Probe mirror throughput at startup**. Most accurate, but adds
  3-5 s to every run for an answer that's stable across a single host's
  lifetime. Rejected: the 95 % heuristic is good enough.

## Consequences

- **Positive**: Sensible defaults for everything from a 4-core
  Raspberry Pi 5 (`JOBS=4, MAX_PARALLEL_DOWNLOADS=8`) to a 64-core
  builder (`JOBS=20, MAX_PARALLEL_DOWNLOADS=20`).
- **Positive**: Operator overrides are explicit and bounded — env var
  values are clamped to the same safety ceiling as the auto-computed
  ones. Setting `MAX_PARALLEL_DOWNLOADS=200` will silently get you 20.
- **Positive**: Telemetry records the *resulting* `jobs` and
  `max_parallel_downloads` so post-incident analysis can see what the
  host actually used, not what was requested.
- **Negative**: The `STREAM_MBIT_PER_CONN=35` constant is empirical
  and host/mirror-dependent. Codified as an env var so operators with
  measurements can override; the default is conservative.
- **Negative**: Loadavg-based scaling reacts on a 1m timescale —
  bursty parallel work in another process won't be reflected for
  ~30s. Acceptable: `update` is a one-shot, not a daemon.
- **Negative**: Three knobs (`MIN_CPU_WORKERS`, `MAX_CPU_WORKERS`,
  `DNF_PARALLEL_CAP`) plus two heuristics (`STREAM_MBIT_PER_CONN`,
  `STREAM_UTILIZATION_PERCENT`) is more surface than a single
  hardcoded number. Documented in README's Configuration Reference;
  no operator should have to read this ADR to override one.
