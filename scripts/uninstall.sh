#!/usr/bin/env bash
# scripts/uninstall.sh — remove elegant-updater installation.

set -Eeuo pipefail

PREFIX="${PREFIX:-/usr/local}"
LIBDIR="${PREFIX}/lib/elegant-updater"
BINDIR="${PREFIX}/bin"
LOGDIR="/var/log/elegant-updater"

if (( EUID != 0 )); then
  echo "fatal: must run as root (sudo)" >&2
  exit 1
fi

echo "Removing elegant-updater installation:"
[[ -L "${BINDIR}/update" ]] && rm -f "${BINDIR}/update" && echo "  removed: ${BINDIR}/update"
[[ -L "${BINDIR}/elegant-updater" ]] && rm -f "${BINDIR}/elegant-updater" && echo "  removed: ${BINDIR}/elegant-updater"
[[ -d "$LIBDIR" ]] && rm -rf "$LIBDIR" && echo "  removed: ${LIBDIR}"

if [[ "${KEEP_LOGS:-1}" == "0" ]]; then
  [[ -d "$LOGDIR" ]] && rm -rf "$LOGDIR" && echo "  removed: ${LOGDIR}"
else
  echo "  preserved: ${LOGDIR} (KEEP_LOGS=0 to remove)"
fi

[[ -e /var/lock/elegant-updater.lock ]] && rm -f /var/lock/elegant-updater.lock

echo "Uninstalled."
