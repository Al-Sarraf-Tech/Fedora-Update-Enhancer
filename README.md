# Fedora Update Enhancer

[![CI](https://github.com/Al-Sarraf-Tech/Fedora-Update-Enhancer/actions/workflows/ci-shell.yml/badge.svg)](https://github.com/Al-Sarraf-Tech/Fedora-Update-Enhancer/actions/workflows/ci-shell.yml)
[![Release](https://img.shields.io/github/v/release/Al-Sarraf-Tech/Fedora-Update-Enhancer)](https://github.com/Al-Sarraf-Tech/Fedora-Update-Enhancer/releases/tag/v1.0.1)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

> CI runs on self-hosted runners managed by the [Haskell Orchestrator](https://github.com/Al-Sarraf-Tech/Haskell-Orchestrator). The pipeline includes a `repo-guard` governance job that verifies repository ownership before all other jobs run.

Unattended Fedora system updater built around `dnf5`. It applies adaptive parallelism, tunes DNF configuration, adjusts repo files to prefer mirrorlists, and handles failing repos with automatic fallback — all in a single invocation.

The canonical command is:

```bash
sudo update
```

---

## What It Does

`elegant-updater.sh` is the sole implementation. It runs a sequence of steps in order:

### 1. Preflight

- Verifies it is running as root.
- Confirms `dnf5` is present at the expected path (`/usr/bin/dnf5` by default).
- Auto-selects the active DNF config file: `/etc/dnf/dnf5.conf` if it exists, otherwise `/etc/dnf/dnf.conf`.

### 2. Adaptive Parallelism

Computes two values from live system state:

**Worker count (`JOBS`)** — derived from CPU core count and the 1-minute load average. On an idle machine the worker count trends toward `MAX_CPU_WORKERS` (default 20). Under load it trends toward `MIN_CPU_WORKERS` (default 10). Always clamped to the actual core count.

**Parallel download count (`MAX_PARALLEL_DOWNLOADS`)** — computed from the fastest active non-virtual network interface (read from `/sys/class/net/*/speed`), divided by `STREAM_MBIT_PER_CONN` (default 35 Mbit/connection), then capped at 95% of that theoretical ceiling to avoid mirror rate-limiting. Also bounded by `JOBS × 2` and the hard cap `DNF_PARALLEL_CAP` (default 20).

Both values are printed in the header before any action is taken.

### 3. DNF Config Tuning

Writes computed and policy values into `[main]` of the active DNF config file using an atomic `awk` + `install`/`mv` approach. Keys written:

| Key | Default | Purpose |
|-----|---------|---------|
| `deltarpm` | `true` | Download binary deltas instead of full RPMs when available |
| `keepcache` | `false` | Discard downloaded RPMs after install to conserve disk |
| `fastestmirror` / `enable_fastestmirror` | `true` | Enable mirror latency probing |
| `max_parallel_downloads` | adaptive | Concurrent download streams |
| `installonly_limit` | `3` | Maximum installed kernel generations to retain |
| `skip_if_unavailable` | `true` | Treat unavailable repos as non-fatal |
| `retries` | `6` | Per-request retry count |
| `timeout` | `15` | Per-request timeout in seconds |
| `minrate` | `100k` | Stall threshold — drop mirrors below this rate |

All values are overridable via environment variables before the write step.

### 4. Repo File Optimization (parallel)

When `PREFER_MIRRORS=1` (default), the script processes all `*.repo` files in `/etc/yum.repos.d/` in parallel (bounded by `JOBS`):

- **Mirrorlist preference**: for each repo section that has both a `baseurl` and a `mirrorlist`/`metalink`, the `baseurl` line is commented out so DNF uses the dynamic mirror source. Sections with only a `baseurl` are left untouched.
- **Failover policy**: `skip_if_unavailable` is set per-section to match the global policy.

Changes are written atomically (temp file → `mv`). A snapshot of all repo files is taken before modification; if a subsequent DNF phase fails due to repo errors, the originals are restored before the retry.

### 5. Metadata Refresh

Clears expired metadata (`dnf5 clean expire-cache`), then runs `dnf5 makecache`. If the installed DNF version supports `--timer`, it is used; otherwise plain `makecache` is called.

### 6. Upgrade

Runs:

```
dnf5 upgrade --refresh --best --allowerasing -y \
  --setopt=max_parallel_downloads=<N> \
  --setopt=skip_if_unavailable=<bool>
```

`--setopt` reinforces the config values on the CLI to handle cases where dnf5 loads a different effective config.

### 7. Repo Fallback Handling

Every DNF phase (`makecache`, `upgrade`) runs through a fallback wrapper. If a phase fails with a repo error signature (`Failed to download metadata for repo`, `All mirrors were tried`, curl errors, etc.):

1. The failing repo names are extracted from the output.
2. Those repos are added to a `DISABLED_REPOS` list.
3. If repo files were modified in step 4, the originals are restored.
4. The phase is retried with `--disablerepo=<name>` for each disabled repo.

At the end of the run a repo coverage summary is printed listing: repos discovered, repos that failed, and any repos that were disabled as fallbacks.

### 8. Cleanup

- `dnf5 autoremove -y` — removes packages no longer needed as dependencies.
- Old installonly packages (typically old kernels) are removed, keeping `INSTALLONLY_LIMIT` generations.
- `dnf5 clean packages` — purges cached RPM files while preserving metadata for the next run.

---

## OS Support

| Target | Status |
|--------|--------|
| Fedora 43 with `dnf5` | Fully supported (primary target) |
| Fedora 41+ with `dnf5` installed | Expected to work |
| Fedora with DNF4 only | Not supported |
| Non-Fedora distributions | Not supported |

---

## Requirements

- Bash
- `dnf5` at `/usr/bin/dnf5`
- Root privileges (`sudo`)

---

## Installation

```bash
git clone https://github.com/Al-Sarraf-Tech/Fedora-Update-Enhancer.git
cd Fedora-Update-Enhancer
chmod +x elegant-updater.sh
```

Install as the system-wide `update` command:

```bash
sudo install -m 0755 elegant-updater.sh /usr/local/bin/update
```

---

## Usage

```bash
# Via installed command
sudo update

# Direct script invocation
sudo ./elegant-updater.sh

# With environment overrides
sudo MAX_PARALLEL_DOWNLOADS=20 PREFER_MIRRORS=1 ./elegant-updater.sh
```

---

## Configuration Reference

All tunables are environment variables. None require editing the script.

| Variable | Default | Description |
|----------|---------|-------------|
| `DNF` | `/usr/bin/dnf5` | Path to the dnf5 binary |
| `DNF_CONF` | auto | DNF config file path; auto-detects dnf5.conf vs dnf.conf |
| `MIN_CPU_WORKERS` | `10` | Minimum parallel workers under load |
| `MAX_CPU_WORKERS` | `20` | Maximum parallel workers on idle systems |
| `JOBS` | adaptive | Override computed worker count directly |
| `DNF_PARALLEL_CAP` | `20` | Hard ceiling on parallel downloads |
| `STREAM_MBIT_PER_CONN` | `35` | Assumed bandwidth per download connection (Mbit/s) |
| `STREAM_UTILIZATION_PERCENT` | `95` | Fraction of theoretical download capacity to use |
| `MAX_PARALLEL_DOWNLOADS` | adaptive | Override computed parallel download count directly |
| `INSTALLONLY_LIMIT` | `3` | Number of installonly package versions to retain |
| `FASTESTMIRROR` | `1` | Enable mirror latency probing (`1`/`0`) |
| `SKIP_IF_UNAVAILABLE` | `1` | Treat unreachable repos as non-fatal (`1`/`0`) |
| `RETRIES` | `6` | Per-request retry count |
| `TIMEOUT` | `15` | Per-request timeout (seconds) |
| `MINRATE` | `100k` | Minimum transfer rate before dropping a mirror |
| `PREFER_MIRRORS` | `1` | Rewrite repo files to prefer mirrorlist/metalink (`1`/`0`) |
| `REPO_DIR` | `/etc/yum.repos.d` | Directory containing `.repo` files |
| `SHOW_REPO_LIST` | `1` | Print discovered repo names in the summary (`1`/`0`) |
| `RUN_UPDATE_SWEEP` | `0` | Run `dnf5 update` after `dnf5 upgrade` (redundant in DNF5; off by default) |

---

## Notes

- No log file is written by default. Pipe output to `tee` if a persistent record is needed.
- No reboot or `needs-restarting` check is performed. Kernel and glibc updates require a manual reboot.
- The script is idempotent: running it multiple times on an up-to-date system is safe.
- ANSI color output is suppressed automatically when stdout is not a terminal.

---

## CI/CD

The pipeline is defined in [`.github/workflows/ci-shell.yml`](.github/workflows/ci-shell.yml) and runs on self-hosted runners managed by the [Haskell Orchestrator](https://github.com/Al-Sarraf-Tech/Haskell-Orchestrator).

Jobs:

| Job | Purpose |
|-----|---------|
| `repo-guard` | Verifies repository context before all other jobs run |
| `lint` | Bash syntax check, ShellCheck, shfmt |
| `test` | Validates scripts (lint-only; no live DNF execution in CI) |
| `security` | gitleaks secrets scan + ShellCheck |
| `sbom` | SBOM generation on `main` pushes |
| `integration` | Syntax and mock-upgrade integration checks |
| `release` | Generates checksums and publishes GitHub Releases on tags |

Triggers: push to `main`, pull requests, version tags (`v*`), and a weekly Monday 04:00 UTC schedule.

---

## License

[MIT](LICENSE)
