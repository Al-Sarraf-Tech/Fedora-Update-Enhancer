# Assurance Document -- Fedora-Update-Enhancer

This document describes the CI/CD quality gates, testing methodology, supply-chain
controls, and security practices applied to the Fedora-Update-Enhancer project.

---

## 1. CI/CD Pipeline Overview

| Workflow | Trigger | Purpose |
|---|---|---|
| **Regression CI (Batched)** | Push to `main`, PRs | Syntax validation, shfmt format check, mock dnf5 integration test |
| **Regression and Security** | Push (all branches), PRs | Multi-language regression detection, Gitleaks secret scanning |
| **Release** | Tag push (`v*`) | Build release tarball, SHA-256 checksum |
| **SBOM Generation** | Push to `main`, weekly schedule | CycloneDX SBOM generation with script hash |

All workflows run on self-hosted runners (`[self-hosted, Linux, X64, docker]`) with
concurrency controls to prevent parallel conflicts.

---

## 2. Quality Gates

### 2.1 Syntax Validation

Every push and pull request triggers `bash -n elegant-updater.sh` inside a clean
Debian container via the Docker runner harness. This catches parse errors before
any code reaches `main`.

### 2.2 Format Validation (shfmt)

The CI pipeline runs `shfmt` as an advisory (non-blocking) check during the syntax
batch. This validates consistent indentation, case statement formatting, and binary
operator placement. The check uses `continue-on-error: true` to avoid blocking
merges while the codebase converges on a canonical format.

### 2.3 Mock Integration Test

A full end-to-end regression test runs `elegant-updater.sh` against a mock `dnf5`
binary. The mock handles `makecache`, `clean`, `upgrade`, `update`, `autoremove`,
`remove`, and `repoquery` commands. This validates the script's control flow,
error handling, and repo fallback logic without requiring a live Fedora package
manager.

### 2.4 Secret Scanning

Gitleaks runs on every push and pull request to detect accidentally committed
secrets, tokens, or private keys.

---

## 3. Supply-Chain Security

### 3.1 SHA-256 Release Checksums

Tagged releases compute a SHA-256 checksum for the release tarball. The checksum
is published alongside the tarball on the GitHub Release page, allowing consumers
to verify artifact integrity against the source commit.

### 3.2 SBOM Generation

A CycloneDX v1.5 SBOM is generated on every push to `main` and on a weekly
schedule. The SBOM includes:

- Project metadata and license (MIT)
- Component inventory with SHA-256 hashes
- Package URL (purl) for dependency tracking

The SBOM is uploaded as a CI artifact with 90-day retention.

### 3.3 Dependency Pinning

All GitHub Actions are pinned to major version tags (`@v4`, `@v2`) to balance
security with maintainability. The project has no runtime dependencies beyond
Bash and `dnf5`.

---

## 4. Release Process

1. Developer tags a commit: `git tag v1.x.x && git push origin v1.x.x`
2. Release workflow builds a tarball containing `elegant-updater.sh`, `README.md`, and `LICENSE`
3. SHA-256 checksum is generated for the tarball
4. GitHub Release is published with tarball and checksum attached

---

## 5. Runner Security

- Runners are self-hosted on controlled infrastructure
- Docker-based isolation for syntax checks via `docker-runner.sh`
- Workflow permissions follow least-privilege (`contents: read` for CI, scoped
  `write` only for release)

---

## 6. Limitations and Future Work

- **shfmt**: Currently advisory (non-blocking). Will be promoted to blocking once
  the codebase is fully formatted.
- **Signed commits**: Not currently enforced. Consider requiring GPG-signed commits
  on `main`.
- **Runner hardening**: Self-hosted runners share the host environment. Consider
  ephemeral runner instances for stronger isolation.
- **SBOM enrichment**: Current SBOM covers the primary script. Future iterations
  could enumerate system dependencies (`dnf5`, `bash`, `coreutils`).
