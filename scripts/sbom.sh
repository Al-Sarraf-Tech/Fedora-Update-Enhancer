#!/usr/bin/env bash
# scripts/sbom.sh — emit a CycloneDX 1.5 SBOM for the project.
#
# Catalogues:
#   - the host bash interpreter (version + path)
#   - dnf5 (version + path) — the only runtime dep beyond the shell
#   - every sourced .sh under bin/ + lib/ + scripts/, with MD5 hash
#   - the project release version (from CHANGELOG.md latest [n.n.n] tag)
#
# Output: dist/sbom-${VERSION}.json (created if missing). Override with
# SBOM_OUTPUT=/path/to/file.json. Schema is CycloneDX 1.5 with bomFormat
# "CycloneDX" and serialNumber a urn:uuid v4-ish identifier.
#
# Hermetic: never reaches the network, never reads /etc beyond
# /etc/os-release, never installs anything. md5sum is the only
# external dep beyond bash + dnf5 + jq.

set -Eeuo pipefail
IFS=$'\n\t'

PROJECT_ROOT="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"

# Detect VERSION from CHANGELOG.md — first "## [n.n.n]" line.
VERSION="${VERSION:-$(awk '
  /^## \[[0-9]+\.[0-9]+\.[0-9]+\]/ {
    match($0, /\[[0-9]+\.[0-9]+\.[0-9]+\]/)
    v = substr($0, RSTART+1, RLENGTH-2)
    print v
    exit
  }' CHANGELOG.md 2>/dev/null)}"
VERSION="${VERSION:-0.0.0-dev}"

OUTPUT="${SBOM_OUTPUT:-dist/sbom-${VERSION}.json}"
mkdir -p "$(dirname "$OUTPUT")"

# Pseudo-random urn:uuid (RFC4122 variant 4-ish; uses /dev/urandom).
gen_urn() {
  local bytes hex
  bytes="$(head -c 16 /dev/urandom | od -An -tx1 | tr -d ' \n')"
  # Force version 4 + variant 10xx
  hex="${bytes:0:8}-${bytes:8:4}-4${bytes:13:3}-a${bytes:17:3}-${bytes:20:12}"
  printf 'urn:uuid:%s' "$hex"
}

iso_now() { date -u +%Y-%m-%dT%H:%M:%SZ; }

# Capture bash version + path
BASH_PATH="$(command -v bash || echo /usr/bin/bash)"
BASH_VER="${BASH_VERSION%%-*}"   # e.g. "5.3.9(1)" -> "5.3.9(1)"
BASH_VER="${BASH_VER%%(*}"        # -> "5.3.9"

# Capture dnf5 version + path. Best-effort: SBOM still valid if dnf5 absent
# (e.g. CI runner where dnf5 isn't installed); record "unknown".
DNF5_PATH="$(command -v dnf5 2>/dev/null || true)"
DNF5_VER="unknown"
if [[ -n "$DNF5_PATH" ]] && DNF5_OUT="$("$DNF5_PATH" --version 2>/dev/null)"; then
  DNF5_VER="$(printf '%s' "$DNF5_OUT" | awk '/^dnf5 version/{print $3; exit}')"
  DNF5_VER="${DNF5_VER:-unknown}"
fi
[[ -z "$DNF5_PATH" ]] && DNF5_PATH="/usr/bin/dnf5"

# JSON-escape a string (ASCII subset).
jescape() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"
  s="${s//$'\r'/\\r}"
  s="${s//$'\t'/\\t}"
  printf '%s' "$s"
}

# Emit one component object for an in-tree script. Args: relative path.
emit_script_component() {
  local path="$1" md5 name
  md5="$(md5sum "$path" | awk '{print $1}')"
  name="$(basename "$path")"
  cat <<JSON
    {
      "type": "file",
      "bom-ref": "pkg:fue/script/${name}@${md5}",
      "name": "$(jescape "$path")",
      "version": "${VERSION}",
      "hashes": [
        {"alg": "MD5", "content": "${md5}"}
      ],
      "scope": "required",
      "description": "Sourced or executed by elegant-updater"
    }
JSON
}

# Build the SBOM into a temp, then atomic-mv into place.
TMP_OUT="$(mktemp "${OUTPUT}.tmp.XXXXXX")"
trap 'rm -f "$TMP_OUT" 2>/dev/null || true' EXIT

URN="$(gen_urn)"
TS="$(iso_now)"

{
  printf '{\n'
  printf '  "bomFormat": "CycloneDX",\n'
  printf '  "specVersion": "1.5",\n'
  printf '  "serialNumber": "%s",\n' "$URN"
  printf '  "version": 1,\n'
  printf '  "metadata": {\n'
  printf '    "timestamp": "%s",\n' "$TS"
  printf '    "tools": [\n'
  printf '      {"vendor": "Al-Sarraf-Tech", "name": "fue-sbom", "version": "%s"}\n' "$VERSION"
  printf '    ],\n'
  printf '    "component": {\n'
  printf '      "type": "application",\n'
  printf '      "bom-ref": "pkg:fue/elegant-updater@%s",\n' "$VERSION"
  printf '      "name": "Fedora-Update-Enhancer",\n'
  printf '      "version": "%s",\n' "$VERSION"
  printf '      "description": "Unattended Fedora updater built around dnf5",\n'
  printf '      "licenses": [{"license": {"id": "MIT"}}]\n'
  printf '    }\n'
  printf '  },\n'
  printf '  "components": [\n'

  # Runtime: bash interpreter
  cat <<JSON
    {
      "type": "application",
      "bom-ref": "pkg:generic/bash@${BASH_VER}",
      "name": "bash",
      "version": "$(jescape "$BASH_VER")",
      "scope": "required",
      "description": "Host shell interpreter (path: $(jescape "$BASH_PATH"))",
      "purl": "pkg:generic/bash@${BASH_VER}"
    }
JSON
  printf ',\n'

  # Runtime: dnf5
  cat <<JSON
    {
      "type": "application",
      "bom-ref": "pkg:rpm/fedora/dnf5@${DNF5_VER}",
      "name": "dnf5",
      "version": "$(jescape "$DNF5_VER")",
      "scope": "required",
      "description": "Package manager (path: $(jescape "$DNF5_PATH"))",
      "purl": "pkg:rpm/fedora/dnf5@${DNF5_VER}"
    }
JSON

  # In-tree scripts (bin + lib + scripts), MD5 hashed
  while IFS= read -r f; do
    printf ',\n'
    emit_script_component "$f"
  done < <(find bin lib scripts -type f -name '*.sh' 2>/dev/null | sort)

  printf '\n  ]\n'
  printf '}\n'
} > "$TMP_OUT"

# Validate via jq if present (defensive — schema not enforced, just JSON
# parse + bomFormat field).
if command -v jq >/dev/null 2>&1; then
  if ! jq -e '.bomFormat == "CycloneDX" and .specVersion == "1.5"' "$TMP_OUT" >/dev/null; then
    printf 'sbom: validation failed — output is not a CycloneDX 1.5 document\n' >&2
    exit 1
  fi
fi

mv -f "$TMP_OUT" "$OUTPUT"
trap - EXIT
printf 'sbom: %s\n' "$OUTPUT"
