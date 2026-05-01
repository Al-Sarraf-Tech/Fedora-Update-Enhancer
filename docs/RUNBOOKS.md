# elegant-updater Runbooks

Operator playbook for diagnosing and recovering from `elegant-updater`
failures. Each entry maps a **symptom** (log line, exit code, telemetry
field) to a **cause**, **diagnose** steps, and **recovery** actions.

Per-failure deep-dives live alongside this file under
`docs/runbooks/<topic>.md`. This index covers every operationally
significant scenario, including ones not tied to a single error code
(transaction rollback, telemetry sink degradation, reboot loop).

Logs:

```bash
# Latest run, structured (when --json is in use)
ls -t /var/log/elegant-updater/run-*.json | head -1 | xargs -I{} jq . {}

# Latest run, text
ls -t /var/log/elegant-updater/run-*.log  | head -1 | xargs cat

# All recent telemetry, condensed
jq -s 'sort_by(.ts) | reverse | .[0:5] |
  map({ts, run_id, exit_code, upgrade_seconds, repos_failed, repos_disabled, reboot_needed})' \
  /var/log/elegant-updater/run-*.json
```

---

## Exit Codes

| Code | Meaning | Runbook |
|---|---|---|
| 0   | Success | — |
| 1   | Pre-flight failed or unrecoverable error | section by symptom below |
| 11  | Lock contention — another run is in progress | `lock-contention` |
| 64  | Argument parse error (unknown flag) | re-run with `--help` |
| 70  | Unsupported OS (not Fedora >= 41) | reset OS expectations |
| 130 | Interrupted (SIGINT / SIGTERM) | re-run when host quiescent |

---

## R-1 — Lock Contention (exit 11)

**Symptom**

```
✖ Another elegant-updater run is in progress (lock /var/lock/elegant-updater.lock)
```

Exits 11. Telemetry not written (lock contention exits before init).

**Cause** Another instance of `elegant-updater` (or a stale lock from a
killed run) holds `/var/lock/elegant-updater.lock` via `flock`.

**Diagnose** (≤30 s)

```bash
ls -la /var/lock/elegant-updater.lock
# Identify the holder
sudo lsof /var/lock/elegant-updater.lock 2>/dev/null
# Or by pid recorded in the lock file body
sudo cat /var/lock/elegant-updater.lock
ps -fp "$(sudo awk '{print $1; exit}' /var/lock/elegant-updater.lock 2>/dev/null)" 2>/dev/null
```

**Recovery**

- Holder is alive and running an upgrade: wait. The lock releases when
  it exits.
- Holder pid exists but is not running `elegant-updater` (stale lock,
  killed mid-run): `sudo rm -f /var/lock/elegant-updater.lock` and re-run.
- Recurring lock contention from a cron or timer: stagger or serialize
  with `systemctl edit elegant-updater.timer` (if installed via timer).

**Prevention** Wrap with `flock -w 0 /var/lock/elegant-updater.lock` in
any wrapper script. The internal `flock -n` already does this; only
external wrappers (cron, ansible) can race.

---

## R-2 — dnf Lock Contention (pre-flight)

**Symptom**

```
✖ rpm database is locked by another process
✖ Another package manager is running (dnf/dnf5/rpm/packagekit)
✖ Pre-flight failed; aborting
```

Exits 1. See also `docs/runbooks/rpm-lock.md` for the full
deep-dive.

**Cause** Another `dnf`/`dnf5`/`rpm`/`packagekitd` process holds the
RPM transaction lock. `elegant-updater` refuses to attempt a
transaction when this is true — concurrent transactions corrupt the
rpmdb.

**Diagnose** (≤1 min)

```bash
sudo fuser /var/lib/rpm/.rpm.lock 2>/dev/null
pgrep -af '(^|/)dnf|^rpm|packagekitd'
systemctl status packagekit
```

**Recovery**

- If `packagekitd` is the holder and you don't want it: `sudo
  systemctl stop packagekit` (and disable in GNOME Software preferences
  if persistent), then re-run.
- If GNOME Software is mid-update: wait for it. PackageKit transactions
  finish in seconds to minutes.
- If holder is a stuck `dnf` or `dnf5`: identify it with `ps -fp
  <PID>`, decide whether to kill (last resort —
  `sudo dnf history rollback` may be needed if the holder was mid-tx).
- One-shot bypass for known-safe concurrent state: `sudo
  FUE_ALLOW_PACKAGEKIT=1 update`. Use sparingly.

---

## R-3 — Partial Transaction Rollback

**Symptom** Upgrade aborts mid-transaction (kill, OOM, power loss). On
the next run:

```
✖ rpmdb: Thread/process N/M failed: Thread died in Berkeley DB library
```

or

```
Error: Transaction test error: package <foo> conflicts with <bar>
```

Telemetry from prior run shows non-zero `exit_code` and absent
`finished_at`.

**Cause** RPM transactions are journaled but not strictly atomic across
all packages — a kill mid-transaction leaves the rpmdb in a recoverable
but unclean state. `elegant-updater` does not trigger rollback itself
(no `--allowerasing` rollback command exists in dnf5); the operator
must.

**Diagnose** (≤2 min)

```bash
# Last transaction
sudo dnf5 history list | head
# Detail of the partial one (use the highest ID)
sudo dnf5 history info <ID>
# Check rpmdb integrity
sudo rpmdb --verifydb 2>&1 | head
# Disk full? (common root cause for kills)
df -h /var
```

**Recovery**

- Clean rpmdb if corrupt:

  ```bash
  sudo rpmdb --rebuilddb
  ```

- Roll back the partial transaction if the package set is now
  inconsistent:

  ```bash
  sudo dnf5 history rollback <ID>      # rolls to state BEFORE <ID>
  ```

  If `dnf5 history rollback` is unavailable (older builds), use
  `dnf5 history undo <ID>` to invert just that transaction.

- Re-run `sudo update`. Pre-flight will catch a corrupt rpmdb again
  and refuse — fix it first.

**Prevention** The pre-flight `/var` free-space check (>=2 GB) catches
the most common cause (disk full mid-download). Don't lower
`FUE_MIN_FREE_VAR_MB` below 2048 unless you know what you're doing.

---

## R-4 — Repo Failover Active

**Symptom**

```
▲ Upgrade transaction retrying with fallbacks: <repo>
▲ Temporary fallbacks active (disabled repos): <repo1> <repo2>
```

Telemetry: `repos_failed > 0` and `repos_disabled > 0`. Run still
exits 0 if the upgrade itself succeeded.

**Cause** One or more repos failed to fetch metadata. `elegant-updater`
extracted the failing names from dnf output, retried with
`--disablerepo=<name>`, and (if it had previously mutated those .repo
files in the repo-tuning phase) restored the snapshot before retry.
Working as designed; this is degraded but functional. See
`docs/runbooks/repo-failure.md` for the full deep-dive.

**Diagnose** (≤2 min)

```bash
jq -r '.repos_failed // empty, .repos_disabled // empty' \
  /var/log/elegant-updater/run-*.json | tail
# Hit the failed repo directly
sudo dnf5 --disablerepo='*' --enablerepo=<repo> makecache
```

**Recovery**

- Transient mirrorlist outage: re-run; usually resolves within minutes.
- Third-party repo (RPM Fusion, docker-ce) misconfigured: inspect
  `/etc/yum.repos.d/<repo>.repo`. Backup is in
  `/tmp/elegant-updater-repo-backup.*` if rollback fired.
- Stale GPG keys: `grep -i gpg /var/log/elegant-updater/run-*.log` and
  re-import per the repo provider's instructions.

---

## R-5 — Telemetry Sink Unreachable

**Symptom** Logs and console output appear normal but no
`/var/log/elegant-updater/run-*.json` is produced. Or the JSON file
appears but is empty / truncated. Or:

```
journald: Failed to send message: Unit elegant-updater.service is not loaded
```

(or similar `systemd-cat` errors).

**Cause** Multiple, ordered most→least common:

1. `FUE_LOG_DIR` (`/var/log/elegant-updater/`) is unwritable —
   permissions changed, mount went read-only, disk full.
2. `--no-journald` was passed (intentional or wrapper-injected) — only
   stdout shows; nothing reaches journald.
3. `systemd-cat` is missing (minimal containers, alpine in a chroot).
   `elegant-updater` falls back silently to text + file.
4. The telemetry file write happens in the EXIT trap; a SIGKILL skips
   it.

**Diagnose** (≤2 min)

```bash
# 1. Permissions and free space
ls -ld /var/log/elegant-updater
sudo touch /var/log/elegant-updater/probe && sudo rm /var/log/elegant-updater/probe
df -h /var/log
# 2. Was --no-journald in effect?
grep -E -- '--no-journald|FUE_LOG_JOURNALD=0' /var/log/elegant-updater/*.log
# 3. systemd-cat availability
command -v systemd-cat
# 4. Was the run killed?
jq -r '.exit_code, .finished_at' /var/log/elegant-updater/run-*.json | tail
```

**Recovery**

- Permissions / mount: `sudo chown root:root /var/log/elegant-updater
  && sudo chmod 0750 /var/log/elegant-updater`. For a read-only mount,
  remount rw or move `FUE_LOG_DIR` (`export
  FUE_LOG_DIR=/var/lib/elegant-updater/log`).
- journald fallback: install `systemd` or accept the file-only fallback
  (no operational impact, just no `journalctl` integration).
- Killed runs: nothing recoverable from that run; rely on the file
  log if `FUE_LOG_FILE_ENABLED=1` (default) — text log is appended
  in real time, telemetry JSON is the casualty.

**Prevention** Monitoring should alert on `count_distinct(run_id) ==
0` over the expected schedule (e.g. nightly cron). The presence of any
new file in `FUE_LOG_DIR` is the cheapest signal.

---

## R-6 — Kernel Update Reboot Loop

**Symptom** Every `sudo update` invocation ends with:

```
▲ Reboot required (kernel/glibc/critical lib updated)
```

Operator reboots, runs `sudo update` again, sees the same warning. The
`reboot_needed` telemetry stays `true` across runs.

**Cause** One of:

1. The newest installed kernel is the running kernel, but
   `/var/run/reboot-required` was created by an unrelated tool and not
   cleaned (stale flag).
2. Multiple kernels installed; the bootloader is selecting an older
   one. `uname -r` shows older than `rpm -q kernel | sort -V | tail
   -1`.
3. `dnf5 needs-restarting --reboothint` is detecting glibc / systemd /
   dbus changes that legitimately require reboot, and a previous
   `update` slipped one in without prompting.
4. Kernel install succeeded but `grub2-mkconfig` did not re-run
   (broken Grub config or read-only `/boot`).

**Diagnose** (≤3 min)

```bash
# Compare running vs installed kernel
uname -r
rpm -q kernel | sort -V | tail
# Stale flag?
ls -la /var/run/reboot-required
# What does dnf think needs restarting?
sudo dnf5 needs-restarting --reboothint
# Bootloader entries
sudo grubby --info=ALL | head -40
# /boot writable?
ls -ld /boot && touch /boot/.probe && rm /boot/.probe
```

**Recovery**

- Stale flag: `sudo rm /var/run/reboot-required` (only if you've
  verified `uname -r` matches the newest installed kernel and
  `needs-restarting` agrees).
- Bootloader picking old kernel: `sudo grubby --set-default
  /boot/vmlinuz-$(rpm -q kernel | sort -V | tail -1 | sed 's/^kernel-//')`,
  then reboot. Verify with `sudo grubby --default-kernel`.
- /boot read-only or full: remount rw, ensure ≥256 MB free
  (`FUE_MIN_FREE_BOOT_MB` enforces this in pre-flight; a loop
  implies the threshold is being hit).
- Genuine pending reboot: just reboot and run `update` once after.
  Telemetry `reboot_needed` should flip to `false`.

**Prevention** Configure `dnf-automatic` or a similar timer to perform
the upgrade off-hours so the reboot is scheduled, not surprise.
`elegant-updater` does *not* reboot on its own — by design.

---

## R-7 — Disk Full Pre-flight

**Symptom**

```
✖ /var free space ###MB < required 2048MB
✖ /boot free space ###MB < required 256MB
```

See also `docs/runbooks/disk-full.md` for the full deep-dive.

**Cause** `/var` (cache + log + rpm DB) or `/boot` (kernel images) is
under threshold. `elegant-updater` refuses to start because a partial
transaction on a full disk is the worst-case state to recover from
(R-3).

**Recovery**

- `/var` full: `sudo dnf5 clean all && sudo journalctl --vacuum-time=7d`.
- `/boot` full: `sudo dnf5 remove $(rpm -q kernel | head -n -2)` to
  trim old kernels (preserves last 2 generations).
- Lower `FUE_MIN_FREE_VAR_MB` only if you accept the rollback risk.

---

## Health Check (post-incident)

After any non-trivial incident, run this 4-step verification:

```bash
# 1. Lock present and unowned?
sudo lsof /var/lock/elegant-updater.lock 2>/dev/null
# 2. rpmdb intact?
sudo rpmdb --verifydb >/dev/null && echo "rpmdb OK"
# 3. Last run exited cleanly?
jq -r '.exit_code' /var/log/elegant-updater/run-*.json | tail -1
# 4. Repos all reachable?
sudo dnf5 repolist --enabled
```

A passing run after recovery should show `exit_code = "0"` and
`repos_disabled` absent or empty.
