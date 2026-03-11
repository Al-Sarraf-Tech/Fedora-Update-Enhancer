# Fedora Update Enhancer

[![Regression CI](https://github.com/jalsarraf0/Fedora-Update-Enhancer/actions/workflows/regression-security.yml/badge.svg)](https://github.com/jalsarraf0/Fedora-Update-Enhancer/actions/workflows/regression-security.yml)
[![Security CI](https://github.com/jalsarraf0/Fedora-Update-Enhancer/actions/workflows/ci-batched.yml/badge.svg)](https://github.com/jalsarraf0/Fedora-Update-Enhancer/actions/workflows/ci-batched.yml)

High-performance unattended Fedora updater powered by `dnf5`.

## Canonical Command

The prevailing command is:

```bash
sudo update
```

In this repository, the implementation is [`elegant-updater.sh`](elegant-updater.sh). You can run it directly or install it as `update`.

## What It Does

`elegant-updater.sh`:

1. Requires root and validates `dnf5`.
2. Auto-selects DNF config (`/etc/dnf/dnf5.conf`, fallback `/etc/dnf/dnf.conf`).
3. Computes adaptive parallelism from CPU load and link speed.
4. Tunes DNF options including:
   - `deltarpm`
   - `keepcache`
   - `fastestmirror` / `enable_fastestmirror`
   - `max_parallel_downloads`
   - `installonly_limit`
   - `skip_if_unavailable`
   - `retries`, `timeout`, `minrate`
5. Optionally rewrites repo files to prefer mirrorlist/metalink and applies safe fallback behavior.
6. Refreshes metadata and runs `dnf5 upgrade --refresh --best --allowerasing -y`.
7. Handles failing repos by retrying with temporary `--disablerepo` fallbacks.
8. Prints repository coverage/fallback summary.
9. Runs cleanup (`autoremove`, old installonly cleanup, `clean packages`).

## OS Support

Supported:

- Fedora Linux with `dnf5` at `/usr/bin/dnf5`
- Fedora 43 is the primary target (matches script banner/output)

Likely to work (not guaranteed):

- Fedora 41+ with `dnf5` installed and active

Not supported:

- Fedora systems that only have DNF4/no `dnf5`
- Non-Fedora Linux distributions
- macOS and Windows

## Requirements

- Bash
- `dnf5`
- Root privileges (`sudo`)

## Installation

```bash
git clone https://github.com/jalsarraf0/Fedora-Update-Enhancer.git
cd Fedora-Update-Enhancer
chmod +x elegant-updater.sh
```

Optional: install as the global `update` command:

```bash
sudo install -m 0755 elegant-updater.sh /usr/local/bin/update
```

## Usage

```bash
sudo update
```

Direct script usage is also valid:

```bash
sudo ./elegant-updater.sh
```

## Configurable Variables

- `DNF`, `DNF_CONF`
- `MIN_CPU_WORKERS`, `MAX_CPU_WORKERS`, `JOBS`
- `DNF_PARALLEL_CAP`, `STREAM_MBIT_PER_CONN`, `STREAM_UTILIZATION_PERCENT`, `MAX_PARALLEL_DOWNLOADS`
- `INSTALLONLY_LIMIT`
- `FASTESTMIRROR`, `SKIP_IF_UNAVAILABLE`, `RETRIES`, `TIMEOUT`, `MINRATE`
- `PREFER_MIRRORS`, `REPO_DIR`, `SHOW_REPO_LIST`
- `RUN_UPDATE_SWEEP`

Example:

```bash
sudo MAX_PARALLEL_DOWNLOADS=20 PREFER_MIRRORS=1 ./elegant-updater.sh
```

## Notes

- No dedicated log file is written by default.
- No reboot/restart check is performed.

## License

[MIT](LICENSE)

## Validation Status (2026-03-03)

- Regression status: PASS
- Commands validated:
  - `bash -n elegant-updater.sh`
  - `sudo DNF=<mock> DNF_CONF=<tmp> REPO_DIR=<tmp> RUN_UPDATE_SWEEP=1 bash ./elegant-updater.sh`
- CI/CD status: all tests passed on `main` (`Regression CI (Batched)` run `22642586949`, `Regression and Security` run `22642586948`).
- Security hygiene: PASS (no hardcoded secrets or private keys detected in tracked files).
