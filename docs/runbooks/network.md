# Runbook: Network / DNS Failure

## Symptom
Pre-flight warns:
```
▲ Cannot reach mirrors.fedoraproject.org — proceeding (may fail)
```
or upgrade fails with curl errors / "All mirrors were tried".

## Diagnosis (≤2 min)
```bash
getent hosts mirrors.fedoraproject.org
curl -sSI --max-time 5 https://mirrors.fedoraproject.org/
ip route
nmcli connection show --active
```

## Resolution

**DNS broken**:
- Check `/etc/resolv.conf` is populated.
- If using systemd-resolved:
  ```bash
  systemctl status systemd-resolved
  resolvectl status
  ```
- Restart networking:
  ```bash
  sudo systemctl restart NetworkManager
  ```

**Outbound blocked (corporate firewall, captive portal)**:
- Test a known-good HTTPS endpoint:
  ```bash
  curl -sSI --max-time 5 https://1.1.1.1/
  ```
- If the proxy needs auth, set:
  ```bash
  export https_proxy=http://user:pass@proxy.corp:3128
  sudo -E update
  ```

**Air-gapped or known-restricted environment**:
- Disable the network probe but keep upgrade attempt:
  ```bash
  sudo FUE_PREFLIGHT_NETWORK=0 update
  ```
- For fully offline operation, point at a local mirror:
  ```bash
  sudo FUE_REPO_DIR=/etc/yum.repos.d.local update
  ```

## Prevention
- For datacenter hosts, deploy a local Fedora mirror and configure
  `mirrorlist=` to point at it.
- Cache `mirrors.fedoraproject.org` in your local resolver.
