# Runbook: rpm Database Lock

## Symptom
Pre-flight aborts with:
```
✖ Another package manager is running (dnf/dnf5/rpm/packagekit)
✖ Pre-flight failed; aborting
```

## Diagnosis (≤1 min)
```bash
ps -ef | grep -E 'dnf|rpm|packagekit' | grep -v grep
sudo lsof /var/lib/rpm/.rpm.lock 2>/dev/null || true
```

## Resolution

**PackageKit is the holder (most common)**:
- GNOME Software / KDE Discover triggered an auto-check. Either wait
  (~30 s) for it to finish, or:
  ```bash
  sudo systemctl stop packagekit
  sudo update
  sudo systemctl start packagekit
  ```
- To allow PackageKit to coexist (warn instead of abort):
  ```bash
  sudo FUE_ALLOW_PACKAGEKIT=1 update
  ```

**Another `dnf5` is running**:
- Check who owns it (`ps -ef`). If it's a stuck process from a prior
  failed run:
  ```bash
  sudo kill <pid>
  # Wait 5s
  sudo update
  ```
- Never `kill -9` mid-transaction — leaves rpm DB inconsistent. If that
  has already happened:
  ```bash
  sudo rm -f /var/lib/rpm/.rpm.lock
  sudo rpm --rebuilddb
  ```

**Lockfile from `update` itself (concurrent invocation)**:
- Indicated by exit code 11.
- Check `/var/lock/elegant-updater.lock` — its first line is `PID TIMESTAMP`.
- If the PID is no longer running, the lock will release on the next attempt.
