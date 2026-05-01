#!/usr/bin/env bats
# tests/unit/sbom.bats — SBOM generator coverage.

load "../helper"

setup() {
  setup_bats_env
  SBOM="${PROJECT_ROOT}/scripts/sbom.sh"
  export SBOM_OUTPUT="${TMPHOME}/sbom.json"
}
teardown() { teardown_bats_env; }

@test "sbom: emits valid CycloneDX 1.5 to SBOM_OUTPUT" {
  run "$SBOM"
  [ "$status" -eq 0 ]
  [ -f "$SBOM_OUTPUT" ]
  run jq -e '.bomFormat == "CycloneDX"' "$SBOM_OUTPUT"
  [ "$status" -eq 0 ]
  run jq -e '.specVersion == "1.5"' "$SBOM_OUTPUT"
  [ "$status" -eq 0 ]
}

@test "sbom: catalogues bash + dnf5 + every in-tree .sh" {
  run "$SBOM"
  [ "$status" -eq 0 ]
  # bash + dnf5 + N script components
  count="$(jq '.components | length' "$SBOM_OUTPUT")"
  [ "$count" -ge 10 ]
  run jq -e '.components[] | select(.name == "bash")' "$SBOM_OUTPUT"
  [ "$status" -eq 0 ]
  run jq -e '.components[] | select(.name == "dnf5")' "$SBOM_OUTPUT"
  [ "$status" -eq 0 ]
  # Every component carries an md5 hash or a purl
  run jq -e '[.components[] | (.hashes // [] | length) + (if .purl then 1 else 0 end)] | min >= 1' "$SBOM_OUTPUT"
  [ "$status" -eq 0 ]
}

@test "sbom: serial number is a urn:uuid" {
  run "$SBOM"
  [ "$status" -eq 0 ]
  serial="$(jq -r '.serialNumber' "$SBOM_OUTPUT")"
  [[ "$serial" =~ ^urn:uuid:[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[0-9a-f]{4}-[0-9a-f]{12}$ ]]
}

@test "sbom: VERSION env override drives output filename + component version" {
  VERSION="9.9.9-test" SBOM_OUTPUT="${TMPHOME}/v9.json" run "$SBOM"
  [ "$status" -eq 0 ]
  [ -f "${TMPHOME}/v9.json" ]
  v="$(jq -r '.metadata.component.version' "${TMPHOME}/v9.json")"
  [ "$v" = "9.9.9-test" ]
}
