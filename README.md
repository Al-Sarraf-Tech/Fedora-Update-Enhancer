# Fedora Update Enhancer

[![CI](https://github.com/Al-Sarraf-Tech/Fedora-Update-Enhancer/actions/workflows/ci-shell.yml/badge.svg)](https://github.com/Al-Sarraf-Tech/Fedora-Update-Enhancer/actions/workflows/ci-shell.yml)
[![Release](https://img.shields.io/github/v/release/Al-Sarraf-Tech/Fedora-Update-Enhancer)](https://github.com/Al-Sarraf-Tech/Fedora-Update-Enhancer/releases)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

Unattended Fedora system updater built around `dnf5`. Adaptive parallelism,
repo failover, structured logging, dry-run, lockfile, and per-run telemetry.

The canonical command is:

```bash
sudo update
```

---

## Quickstart

```bash
git clone https://github.com/Al-Sarraf-Tech/Fedora-Update-Enhancer.git
cd Fedora-Update-Enhancer
sudo make install
sudo update --dry-run    # preview
sudo update              # apply
```

`make install` lays the orchestrator + libs under
`/usr/local/lib/elegant-updater/` and adds `update` + `elegant-updater`
symlinks in `/usr/local/bin/`.

## Project Layout

```
.
├── bin/elegant-updater.sh         # thin orchestrator
├── lib/                           # single-purpose modules
│   ├── core.sh                    # pure helpers (no I/O)
│   ├── log.sh                     # text/JSON logs + journald + telemetry
│   ├── system.sh                  # host detection (Fedora ver, CPU, link)
│   ├── lock.sh                    # flock concurrency control
│   ├── preflight.sh               # disk/lock/network/root checks
│   ├── postflight.sh              # reboot-needed + summary
│   ├── dnf.sh                     # dnf5 ops + config tuning
│   └── repo.sh                    # repo file mutation + fallback
├── tests/                         # bats test suite
│   ├── unit/                      # 45 unit tests
│   ├── integration/               # 6 integration tests + 2 golden
│   ├── golden/                    # output-stability baselines
│   ├── mocks/                     # mock dnf5 for hermetic tests
│   └── helper.bash                # shared setup/teardown
├── docs/
│   ├── adr/                       # 8 architecture decision records
│   └── runbooks/                  # 4 failure-mode runbooks
├── scripts/
│   ├── install.sh                 # atomic FHS install
│   ├── uninstall.sh
│   └── s-tier-audit.sh            # single-command tier audit
├── Makefile
├── README.md
├── CHANGELOG.md
├── ASSURANCE.md
└── elegant-updater.sh             # legacy v1 shim (deprecated)
```

## What It Does

`bin/elegant-updater.sh` runs eight phases in order:

### 1. Argument parsing + lib sourcing
Flags resolved before any I/O so `--json` and `--debug` apply to startup.

### 2. Pre-flight (`lib/preflight.sh`)
- root check
- dnf5 binary present
- `/var` ≥ 2 GB free, `/boot` ≥ 256 MB free
- rpm DB not held by another dnf/PackageKit/rpm
- DNS + HTTPS reachability to `mirrors.fedoraproject.org` (warning only)

### 3. Adaptive parallelism (`lib/core.sh`, `lib/system.sh`)
| Value | Source |
|-------|--------|
| `JOBS` | core count + 1m loadavg, clamped to `[MIN_CPU_WORKERS, MAX_CPU_WORKERS]` |
| `MAX_PARALLEL_DOWNLOADS` | fastest active link Mb/s ÷ `STREAM_MBIT_PER_CONN`, capped at 95% utilization, bounded by `JOBS×2` and `DNF_PARALLEL_CAP` |

### 4. dnf config tuning (`lib/dnf.sh`)
Atomically writes computed values into `[main]` of the active dnf config
(`dnf5.conf` if present, else `dnf.conf`). Keys: `deltarpm`, `keepcache`,
`fastestmirror`, `enable_fastestmirror`, `max_parallel_downloads`,
`installonly_limit`, `skip_if_unavailable`, `retries`, `timeout`, `minrate`.

### 5. Repo file optimization (`lib/repo.sh`)
For each `*.repo`, in parallel (bounded by `JOBS`):
- if both `baseurl` and `metalink`/`mirrorlist` are present, comments out
  `baseurl=` so dnf uses the dynamic mirror source
- sets `skip_if_unavailable` per-section to match policy
- atomic write with snapshot/rollback on failure

### 6. Metadata refresh + upgrade (`lib/dnf.sh`)
- `dnf5 clean expire-cache`
- `dnf5 makecache --timer -q` (or plain `makecache` on older dnf)
- `dnf5 upgrade --refresh --best --allowerasing -y --setopt=max_parallel_downloads=N`

Both phases are wrapped by `run_dnf_with_repo_fallback`: on repo errors,
extracts the failing repo names, restores any modified repo files, and
retries with `--disablerepo=<name>`.

### 7. Cleanup
- `dnf5 autoremove -y`
- old installonly packages (kernels) removed (preserving
  `INSTALLONLY_LIMIT` generations)
- `dnf5 clean packages` (preserves metadata cache)

### 8. Post-flight (`lib/postflight.sh`)
- reboot-needed detection
- last transaction id captured to telemetry
- coverage summary (repos discovered / failed / disabled)

## OS Support

| Target | Status |
|--------|--------|
| Fedora 44 with `dnf5` | Primary target (auto-detected) |
| Fedora 43 with `dnf5` | Supported |
| Fedora 41–42 with `dnf5` | Best-effort (warns) |
| Fedora ≤ 40 | Not supported |
| Non-Fedora | Not supported (exits 70) |

## Requirements

- bash ≥ 4
- `dnf5` at `/usr/bin/dnf5` (override via `FUE_DNF`)
- `flock` (util-linux), `systemd-cat` (systemd) — graceful degradation
  if missing
- root privileges (`sudo`)
- For tests: `bats-core` (`sudo dnf install bats`)

## Usage

```bash
# Apply updates (canonical)
sudo update

# Preview without applying
sudo update --dry-run

# Structured JSON logs to stdout
sudo update --json

# Debug-level logging
sudo update --debug

# Run the tier audit
sudo update --audit

# Direct script invocation (development)
sudo bin/elegant-updater.sh --dry-run --no-banner

# Environment overrides
sudo MAX_PARALLEL_DOWNLOADS=12 PREFER_MIRRORS=1 update
```

## Configuration Reference

All tunables are environment variables. None require editing source.

### Sizing
| Variable | Default | Description |
|----------|---------|-------------|
| `MIN_CPU_WORKERS` | `10` | Lower bound on adaptive worker count |
| `MAX_CPU_WORKERS` | `20` | Upper bound on adaptive worker count |
| `JOBS` | adaptive | Override computed worker count |
| `DNF_PARALLEL_CAP` | `20` | Hard ceiling on parallel downloads |
| `STREAM_MBIT_PER_CONN` | `35` | Assumed Mb/s per download connection |
| `STREAM_UTILIZATION_PERCENT` | `95` | Fraction of theoretical max to use |
| `MAX_PARALLEL_DOWNLOADS` | adaptive | Override computed parallel downloads |

### dnf policy
| Variable | Default | Description |
|----------|---------|-------------|
| `FUE_DNF` (`DNF`) | `/usr/bin/dnf5` | dnf binary |
| `FUE_DNF_CONF` (`DNF_CONF`) | auto | dnf config path |
| `INSTALLONLY_LIMIT` | `3` | Number of kernel generations to retain |
| `FASTESTMIRROR` | `1` | Enable mirror latency probing |
| `SKIP_IF_UNAVAILABLE` | `1` | Treat unreachable repos as non-fatal |
| `RETRIES` | `6` | Per-request retry count |
| `TIMEOUT` | `15` | Per-request timeout (seconds) |
| `MINRATE` | `100k` | Min transfer rate before dropping a mirror |
| `PREFER_MIRRORS` | `1` | Rewrite repo files to prefer mirrorlists |
| `FUE_REPO_DIR` (`REPO_DIR`) | `/etc/yum.repos.d` | Directory of `*.repo` files |
| `RUN_UPDATE_SWEEP` | `0` | Run `dnf5 update` after `upgrade` (redundant in DNF5) |
| `FUE_SHOW_REPO_LIST` (`SHOW_REPO_LIST`) | `1` | List repos in summary |

### Pre-flight
| Variable | Default | Description |
|----------|---------|-------------|
| `FUE_PREFLIGHT_FATAL` | `1` | Abort on pre-flight failure (`0` to warn-only) |
| `FUE_PREFLIGHT_NETWORK` | `1` | Probe `mirrors.fedoraproject.org` |
| `FUE_NETWORK_PROBE_HOST` | `mirrors.fedoraproject.org` | Probe target |
| `FUE_MIN_FREE_VAR_MB` | `2048` | Required `/var` free space |
| `FUE_MIN_FREE_BOOT_MB` | `256` | Required `/boot` free space |
| `FUE_ALLOW_PACKAGEKIT` | `0` | Allow PackageKit running concurrently |

### Logging + telemetry
| Variable | Default | Description |
|----------|---------|-------------|
| `FUE_LOG_LEVEL` (`LOG_LEVEL`) | `info` | `debug`/`info`/`warn`/`error` |
| `FUE_LOG_FORMAT` (`LOG_FORMAT`) | `text` | `text` or `json` |
| `FUE_LOG_DIR` | `/var/log/elegant-updater` | Per-run log directory |
| `FUE_LOG_FILE_ENABLED` | `1` | Write to `$FUE_LOG_DIR/run-<id>.log` |
| `FUE_LOG_JOURNALD` (`LOG_JOURNALD`) | `1` | Send to journald via `systemd-cat` |
| `FUE_RUN_ID` | timestamp+pid | Run correlation id |

### Lockfile
| Variable | Default | Description |
|----------|---------|-------------|
| `FUE_LOCK_FILE` | `/var/lock/elegant-updater.lock` | Concurrency lock |

## Exit Codes

| Code | Meaning |
|------|---------|
| 0    | Success |
| 1    | Pre-flight failed or unrecoverable error |
| 11   | Lock contention — another run is in progress |
| 64   | Argument parse error (unknown flag) |
| 70   | Unsupported OS (not Fedora ≥ 41) |
| 130  | Interrupted (SIGINT/SIGTERM) |

## Testing

```bash
make test                    # all bats tests (51 currently)
make test-unit               # 45 unit
make test-integration        # 6 + 2 golden
make lint                    # shellcheck
make audit                   # tier rubric audit
```

## Documentation

- `docs/adr/` — 8 architecture decision records
- `docs/runbooks/` — 4 runbooks for the most common failures
- `ASSURANCE.md` — CI gates + supply chain controls
- `CHANGELOG.md` — release history

## License

[MIT](LICENSE)
