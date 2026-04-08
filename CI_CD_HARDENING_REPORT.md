# CI/CD Hardening Report -- Fedora-Update-Enhancer

**Date:** 2026-03-14
**Branch:** `ci/assurance-hardening`

---

## Summary

This report documents the CI/CD hardening changes applied to the
Fedora-Update-Enhancer repository, covering SBOM generation, format validation,
and assurance documentation.

---

## Changes Made

### 1. shfmt Format Validation (ci-batched.yml)

**What:** Added a `shfmt` format check step to the existing syntax batch in the
Regression CI (Batched) workflow.

**How:** The step runs `shfmt -d -i 2 -ci -bn elegant-updater.sh` with
`continue-on-error: true`, making it an advisory (non-blocking) check. If `shfmt`
is not installed on the runner, the step emits a warning and skips gracefully.

**Why:** Format consistency reduces review friction and prevents style-related
merge conflicts. The non-blocking mode allows incremental adoption.

### 2. SBOM Workflow (sbom.yml)

**What:** New workflow `.github/workflows/sbom.yml` that generates a CycloneDX
v1.5 SBOM on every push to `main` and weekly (Monday 06:00 UTC).

**How:** Pure shell-based SBOM generation (no external tools required). Computes
SHA-256 hash of `elegant-updater.sh`, embeds it in a CycloneDX JSON manifest,
and uploads as a CI artifact with 90-day retention.

**Why:** SBOM generation is increasingly required for software supply-chain
compliance (Executive Order 14028, NIST SP 800-218). For a single-script project,
a lightweight shell-based approach is appropriate and avoids adding complex
toolchain dependencies.

### 3. ASSURANCE.md

**What:** Created a comprehensive assurance document describing all CI/CD gates,
testing methodology, supply-chain controls, and security practices.

**Why:** Provides a single reference for auditors, contributors, and downstream
users to understand the project's quality assurance posture.

### 4. CI_CD_HARDENING_REPORT.md

**What:** This document, recording what was changed and why.

---

## Existing Controls (Unchanged)

| Control | Status | Notes |
|---|---|---|
| Bash syntax check (`bash -n`) | Active | Runs in Docker container |
| Mock dnf5 integration test | Active | Full script execution with mock binary |
| Gitleaks secret scanning | Active | Every push and PR |
| SHA-256 checksums | Active | On release artifacts |
| Concurrency controls | Active | All workflows have cancel-in-progress |
| Least-privilege permissions | Active | `contents: read` for CI workflows |

---

## Risk Assessment

| Risk | Mitigation | Residual Risk |
|---|---|---|
| shfmt not installed on runner | Graceful skip with warning | Low -- format check is advisory |
| SBOM generation fails | Does not block main CI pipeline | Low -- separate workflow |
| Self-hosted runner compromise | Docker isolation for syntax checks, least-privilege permissions | Medium -- shared host environment |

---

## Validation

- [x] All YAML files pass `yamllint` syntax validation
- [x] Existing CI workflows unchanged in behavior
- [x] New shfmt step is non-blocking (`continue-on-error: true`)
- [x] SBOM workflow uses proper concurrency and permissions
- [x] No secrets or credentials added

---

## Recommendations for Future Hardening

1. **Promote shfmt to blocking** once `elegant-updater.sh` is fully formatted
2. **Add signed commits enforcement** on the `main` branch
3. **Consider ephemeral runners** for stronger isolation
4. **Add SBOM to release artifacts** alongside the tarball and checksum
5. **Pin Actions to commit SHAs** for maximum supply-chain security
