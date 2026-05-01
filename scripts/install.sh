#!/usr/bin/env bash
# scripts/install.sh — install elegant-updater system-wide.
# Layout (FHS-compliant):
#   /usr/local/lib/elegant-updater/         (orchestrator + libs)
#   /usr/local/bin/update                   (symlink to orchestrator)
#   /usr/local/bin/elegant-updater          (symlink to orchestrator)
#   /var/log/elegant-updater/               (run logs)
#   /var/lock/elegant-updater.lock          (concurrency lock)

set -Eeuo pipefail

PROJECT_ROOT="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PREFIX="${PREFIX:-/usr/local}"
LIBDIR="${PREFIX}/lib/elegant-updater"
BINDIR="${PREFIX}/bin"
LOGDIR="/var/log/elegant-updater"

if (( EUID != 0 )); then
  echo "fatal: must run as root (sudo)" >&2
  exit 1
fi

echo "Installing elegant-updater into:"
echo "  libdir: ${LIBDIR}"
echo "  bindir: ${BINDIR}"
echo "  logdir: ${LOGDIR}"

# Fresh libdir (atomic — write to .new, swap)
NEWDIR="${LIBDIR}.new.$$"
trap 'rm -rf "$NEWDIR" 2>/dev/null || true' EXIT

install -d -m 0755 "$NEWDIR"
install -d -m 0755 "$NEWDIR/lib"
install -d -m 0755 "$NEWDIR/bin"
install -d -m 0755 "$NEWDIR/scripts"
install -m 0755 "$PROJECT_ROOT/bin/elegant-updater.sh" "$NEWDIR/bin/elegant-updater.sh"
for f in "$PROJECT_ROOT"/lib/*.sh; do
  install -m 0644 "$f" "$NEWDIR/lib/$(basename "$f")"
done
install -m 0755 "$PROJECT_ROOT/scripts/uninstall.sh" "$NEWDIR/scripts/uninstall.sh"
install -m 0755 "$PROJECT_ROOT/scripts/s-tier-audit.sh" "$NEWDIR/scripts/s-tier-audit.sh"

# Swap: remove old, rename new
if [[ -d "$LIBDIR" ]]; then
  rm -rf "$LIBDIR.bak.$$" 2>/dev/null || true
  mv "$LIBDIR" "$LIBDIR.bak.$$"
fi
mv "$NEWDIR" "$LIBDIR"
trap - EXIT
rm -rf "$LIBDIR.bak.$$" 2>/dev/null || true

# Symlinks
install -d -m 0755 "$BINDIR"
ln -sf "${LIBDIR}/bin/elegant-updater.sh" "${BINDIR}/elegant-updater"
ln -sf "${LIBDIR}/bin/elegant-updater.sh" "${BINDIR}/update"

# Log dir
install -d -m 0750 "$LOGDIR"

echo "Installed."
echo "Run: sudo update"
echo "Or:  sudo elegant-updater --dry-run"
echo
echo "Verifying installation..."
"${BINDIR}/update" --version
