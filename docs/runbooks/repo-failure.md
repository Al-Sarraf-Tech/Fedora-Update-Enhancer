# Runbook: Repository Failure

## Symptom
Operator sees `▲ Upgrade transaction retrying with fallbacks: <repo>` in
logs, or telemetry shows `repos_failed > 0` and `repos_disabled > 0`.

## Diagnosis (≤2 min)

1. Identify failed repos:
   ```bash
   jq -r '.repos_failed // empty' /var/log/elegant-updater/run-*.json | tail
   ```
2. Confirm reachability:
   ```bash
   curl -sSI https://mirrors.fedoraproject.org/ | head -1
   ```
3. Check the failed repo's mirror health:
   ```bash
   sudo dnf5 repolist --enabled | grep <repo>
   sudo dnf5 --disablerepo='*' --enablerepo=<repo> makecache
   ```

## Resolution

**Cause: mirrorlist outage**
- Confirm `https://mirrors.fedoraproject.org/...` returns 200 from the host.
- If yes, fault is transient — re-run `sudo update`.

**Cause: third-party repo (e.g. RPM Fusion, docker-ce) misconfigured**
- Inspect `/etc/yum.repos.d/<repo>.repo`.
- Check if `baseurl=` is unreachable. The script may have rolled back its
  `prefer_mirrorlist` mutation; the original is preserved in the snapshot.
- Confirm the repo is intentional. If yes, contact the repo owner. If no,
  remove the file and re-run.

**Cause: GPG key trust expired**
- `dnf5` will refuse metadata. Search the log file for `Key import` errors:
  ```bash
  grep -i 'gpg' /var/log/elegant-updater/run-*.log
  ```
- Re-import the key per the repo provider's instructions.

## Prevention
- Use `FUE_PREFER_MIRRORS=1` (default) so the script picks healthy mirrors
  automatically.
- For mission-critical hosts, pin third-party repos' `baseurl=` explicitly
  rather than relying on dynamic mirrors that may go cold.
