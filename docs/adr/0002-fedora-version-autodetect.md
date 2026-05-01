# ADR 0002: Auto-detect Fedora Version

## Status
Accepted (2026-05-01)

## Context
v1.x hardcoded `Fedora 43 Update — Snake` in the banner. That broke trust
on Fedora 44 hosts (the literal banner contradicted reality) and forced
a release each Fedora cycle just to update a string.

## Decision
Build the banner subtitle from `/etc/os-release` (`ID`, `VERSION_ID`,
`PRETTY_NAME`). Validate that we're on a supported Fedora release:

| Result                                  | Behavior              |
|-----------------------------------------|-----------------------|
| Fedora ≥ 43                             | Proceed silently      |
| Fedora 41–42                            | Warn, proceed         |
| Fedora < 41 or non-Fedora               | Error, exit 70        |

`build_banner_subtitle()` falls back to `<PRETTY_NAME> Update` for unknown
distributions so test environments and forks remain functional.

## Consequences
**Positive**
- One release works across Fedora releases.
- Diagnostic output ("OS: Fedora Linux 44 (Cinnamon)") matches reality.
- Unsupported environments fail fast with a clear error, not corrupted dnf
  state.

**Negative**
- Detection requires `/etc/os-release` (universal on systemd hosts).
- The `validate_fedora_supported` thresholds need maintenance as Fedora's
  release support lifecycle moves.
