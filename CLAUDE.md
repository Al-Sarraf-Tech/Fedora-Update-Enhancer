# CLAUDE.md — Fedora-Update-Enhancer

Single Bash script (`elegant-updater.sh`) for high-performance unattended Fedora updates
via `dnf5`. Installed as `sudo update` on this host via symlink at `/usr/local/sbin/update`
or `~/scripts/update`.

---

## Organizational Directive (Claude Only)

> **This directive applies ONLY when Claude Code is in use — it is a standing operational policy, not a suggestion.**
>
> Claude operates in this repository as a structured internal engineering organization: single point of contact, adaptive team complexity (Tier 0–4), mandatory review on all work, batch processing, and parallelization where safe. Full directive: `~/.claude/CLAUDE.md`.

---

## Usage

```bash
# Normal run (as root or via sudo)
sudo update

# Or directly
sudo bash elegant-updater.sh
```

The canonical invocation on this host is `sudo update`.

---

## Tunables (environment variables)

| Variable | Purpose |
|---|---|
| `JOBS` | Parallel jobs for dnf5 |
| `MAX_PARALLEL_DOWNLOADS` | Cap on concurrent downloads |
| `DNF_PARALLEL_CAP` | Hard cap on DNF parallelism |
| `FASTESTMIRROR` | Enable fastest mirror selection |
| `PREFER_MIRRORS` | Mirror preference list |
| `RUN_UPDATE_SWEEP` | Run a post-update sweep |
| `SHOW_REPO_LIST` | Print repo list during run |

---

## What the Script Does

1. Detects available CPU cores and sets adaptive `dnf5` parallelism.
2. Optionally enables fastest-mirror selection and repo failover.
3. Runs `dnf5 upgrade` with configured parallelism.
4. Optionally runs a post-update sweep (cleanup, orphan check).
5. Reports what changed.

---

## Coding Conventions (maintain when editing)

- `#!/usr/bin/env bash` + `set -Eeuo pipefail`
- All output uses the defined colour/styling helpers (`hr`, `ttl`, `ok`, `warn`,
  `err`, `note`). Do not use raw `echo` for user-facing output.
- The script must be idempotent — safe to run multiple times in sequence.
- Prefer `dnf5` over `dnf`. Do not fall back to `dnf4` commands.
- Never add interactive prompts. This is an unattended updater.
- Validate that `dnf5` is available with `command -v` before use.

---

## Do Not Change

- The core `dnf5 upgrade` invocation without testing on a real Fedora 43 system.
- Colour styling applied outside of a terminal check — the `[[ -t 1 ]]` guard
  prevents ANSI codes in cron/log output.

---

## Validation

```bash
shellcheck elegant-updater.sh
sudo bash elegant-updater.sh   # real validation requires a Fedora 43 host
```

---

## Toolchain

| Tool | Path | Version |
|---|---|---|
| bash | `/usr/bin/bash` | system |
| shellcheck | `/usr/bin/shellcheck` | system (dnf) |
| Go | `/go/bin/go` | 1.26.1 — not used by this repo |
| Rust | `/usr/bin/rustc` | 1.93.1 — not used by this repo |
| Python | `/usr/bin/python3` | 3.14.3 — not used by this repo |

This repo is pure Bash. No build step required.


---

## CI/CD Pipeline (Enforced)

This repository's CI/CD pipeline is **generated and managed by the Haskell CI Orchestrator** (`~/git/haskell-ci-orchestrator`). Do not manually edit `.github/workflows/ci.yml` — changes will be overwritten on the next sync.

**Directives:**
- All CI/CD runs through the unified `ci.yml` pipeline (lint → test → security → sbom → docker → integration → release)
- **Never release for macOS** — no macOS runners, no macOS release targets
- **Never use the Gentoo runner** — all jobs target `[self-hosted, unified-all]`
- **Never touch `haskell-money` or `haskell-ref`** — hard-denied by the orchestrator
- Pipeline changes go through the orchestrator catalog (`CI.Catalog`), not direct YAML edits
- The orchestrator validates, generates, and syncs workflows across all 15 repos
