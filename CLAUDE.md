# CLAUDE.md — Fedora-Update-Enhancer

Shell-based Fedora update enhancement scripts.

## Build

No compiled artifacts — shell scripts only.

```bash
bash -n elegant-updater.sh
```

## Test

```bash
bash -n elegant-updater.sh
shellcheck elegant-updater.sh
```

## Lint

```bash
shellcheck elegant-updater.sh
```

## Shell Standards
- Use `#!/usr/bin/env bash` and `set -euo pipefail`.
- Quote variable expansions. Use functions for non-trivial logic. Validate binaries with `command -v`.
- Send errors to stderr. Use traps for cleanup. Make scripts idempotent.
- Run `shellcheck` for validation.
