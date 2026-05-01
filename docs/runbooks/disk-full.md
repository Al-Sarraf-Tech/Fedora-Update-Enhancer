# Runbook: Disk Full Pre-flight Failure

## Symptom
Pre-flight aborts with:
```
✖ /var free space ###MB < required 2048MB
✖ Pre-flight failed; aborting
```

## Diagnosis (≤1 min)
```bash
df -hT /var /boot
sudo du -sh /var/cache/* 2>/dev/null | sort -h | tail
```

## Resolution

**Quick wins (in order)**
1. **Clean cached RPMs**:
   ```bash
   sudo dnf5 clean all
   sudo journalctl --vacuum-time=14d
   ```
2. **Trim coredumps** (if any):
   ```bash
   sudo coredumpctl list
   sudo coredumpctl --remove
   ```
3. **Trim old kernels** (the script does this on success; force it):
   ```bash
   sudo dnf5 remove --oldinstallonly
   ```
4. **Inspect `/var/log/`**:
   ```bash
   sudo du -sh /var/log/*
   ```

**If `/boot` is the problem (typical: < 256 MB free)**:
- Old kernels are NOT auto-removed if the host kept `installonly_limit`
  high. Confirm:
  ```bash
  rpm -q kernel-core | sort
  ```
- Remove explicit old kernel:
  ```bash
  sudo dnf5 remove kernel-core-X.Y.Z
  ```

## Override

For known-tight hosts where the threshold is too aggressive:
```bash
sudo FUE_MIN_FREE_VAR_MB=1024 FUE_MIN_FREE_BOOT_MB=128 update
```
This is operator's choice; failed transactions during low-disk are slow
to recover.

## Prevention
- Set `installonly_limit=2` (default in this script is 3) for tight `/boot`.
- Monitor `/var` via your observability stack; alert at 80% full.
