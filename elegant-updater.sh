#!/usr/bin/env bash
# Compatibility shim — v2 entry is bin/elegant-updater.sh.
# Kept at repo root for tooling and historical paths that pointed here.
# Removed in 3.0.0.
set -Eeuo pipefail
__here="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "${__here}/bin/elegant-updater.sh" "$@"
