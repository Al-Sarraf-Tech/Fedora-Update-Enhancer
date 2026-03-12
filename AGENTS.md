# Fedora-Update-Enhancer AGENTS

## Codex-Only Organizational Directive

This section is a mandatory Codex-only operating directive for this host-impacting Fedora updater repo. It applies only when Codex is the acting tool here. It is a directive, not a suggestion. Claude is a separate organization with its own instructions; keep shared repo facts compatible, but do not let Claude-specific policy override Codex policy.

- Operate as one accountable engineering organization with a single external voice; do not expose fragmented internal deliberation.
- Classify the task by size and risk before non-trivial work, then scale discovery, implementation, QA, security, CLI/UX, docs, and reliability review accordingly.
- Research before significant change. Understand the repo's current architecture, entrypoints, toolchain, and operational constraints before editing.
- Review everything touched. Code, tests, scripts, configs, workflows, docs, prompts, and user-facing text all require review before delivery.
- Batch related work, parallelize safe independent workstreams, and keep the final change set coherent and minimal.
- Use host parallelism adaptively. This host has 20 cores; prefer `$(nproc)` or repo-native job selection over fixed counts, and leave headroom when the task is small, interactive, or sharing the machine.
- Keep repo-specific instructions authoritative. Do not let generic agent habits override the constraints in this file or the codebase.

**Agent boundary:** Claude Code operates in this repo under its own separate directive in `CLAUDE.md`. That file is Claude's territory. This file is Codex's territory. Neither directive governs the other agent.

## What This Repo Does

This repo contains `elegant-updater.sh`, a high-impact unattended Fedora updater built around `dnf5`, adaptive parallelism, mirror handling, and cleanup steps. On this machine the canonical invocation is often `sudo update`, but the repo file is `elegant-updater.sh`.

## Main Entrypoints

- `elegant-updater.sh`: the project.
- `README.md`: supported usage, tunables, and validation notes.

## Commands

- `bash -n elegant-updater.sh`
- `shellcheck elegant-updater.sh`
- `sudo bash elegant-updater.sh`

## Repo-Specific Constraints

- This script is intentionally unattended; do not add prompts.
- Keep it `dnf5`-first; do not silently degrade to older package-manager behavior.
- Preserve the terminal color guard so non-TTY output stays clean.
- Keep adaptive job calculation and repo fallback logic reviewable.
- Treat changes as host-maintenance changes that can affect the whole system.

## Agent Notes

- Prefer static checks unless the task explicitly requires a real updater run.
- Call out any change that alters repo handling, cleanup behavior, or parallelism logic.
