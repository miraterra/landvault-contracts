#!/usr/bin/env bash
#
# Level-1 static spec diff for the Discover Pod consumer contract.
# Invoked by `make level1`. Diffs the consumer-required OpenAPI against the
# PROVIDER spec using oasdiff. The provider spec is READ-ONLY input — this
# runner writes nothing outside landvault-contracts (oasdiff goes to a
# repo-local bin/).
#
# oasdiff PROVISIONING (explicit, deterministic, pinned):
#   If oasdiff is on PATH it is used as-is. Otherwise a PINNED version
#   (OASDIFF_VERSION below) is downloaded to a repo-local bin/. The pinned
#   version is the single source of truth — acquisition is not left to chance.
#
# PROVIDER_SPEC (level1 only): a single canonical env var that accepts EITHER a
#   URL or a filesystem path. http(s):// is fetched; anything else is a path.
#   Interim source (until PR #80 merges) — the provider OpenAPI on branch
#   data-2026-spec-conformance-v3 of mt-landvault-api:
#     git -C <mt-landvault-api> show \
#       data-2026-spec-conformance-v3:mt-landvault-api/docs/openapi.yaml \
#       > /tmp/provider-openapi.yaml
#     PROVIDER_SPEC=/tmp/provider-openapi.yaml make level1
#   Re-point at provider main once PR #80 merges.
#
# NO SILENT PASS: if PROVIDER_SPEC is unset or unreachable, level1 exits with a
#   distinct non-zero status (3) and a SKIPPED/non-conformant banner — it never
#   exits 0 as if "the specs agree".
#
# Exit codes:
#   0  — oasdiff ran and the specs are compatible (no breaking changes)
#   1  — oasdiff ran and reported breaking changes (diff produced)
#   2  — usage / tooling error (download failed, oasdiff unusable)
#   3  — SKIPPED: PROVIDER_SPEC unset or unreachable (NOT a pass)
set -euo pipefail

OASDIFF_VERSION="1.20.0"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
BIN_DIR="${REPO_ROOT}/bin"
CONSUMER_SPEC="${SCRIPT_DIR}/../consumer-openapi.yaml"

skip() { echo "level1: SKIPPED — $*" >&2; echo "level1: this is NOT a pass (PROVIDER_SPEC must be set and reachable)." >&2; exit 3; }
fail_tool() { echo "level1: $*" >&2; exit 2; }

# --- Locate or provision oasdiff -------------------------------------------
resolve_oasdiff() {
  if command -v oasdiff >/dev/null 2>&1; then
    echo "oasdiff"; return 0
  fi
  local local_bin="${BIN_DIR}/oasdiff"
  if [ -x "${local_bin}" ]; then
    echo "${local_bin}"; return 0
  fi

  local os arch asset
  os="$(uname -s)"
  arch="$(uname -m)"
  case "${os}" in
    Darwin) asset="oasdiff_${OASDIFF_VERSION}_darwin_all.tar.gz" ;;
    Linux)
      case "${arch}" in
        x86_64|amd64) asset="oasdiff_${OASDIFF_VERSION}_linux_amd64.tar.gz" ;;
        aarch64|arm64) asset="oasdiff_${OASDIFF_VERSION}_linux_arm64.tar.gz" ;;
        *) fail_tool "unsupported Linux arch: ${arch}" ;;
      esac ;;
    *) fail_tool "unsupported OS for oasdiff auto-provision: ${os}" ;;
  esac

  local url="https://github.com/oasdiff/oasdiff/releases/download/v${OASDIFF_VERSION}/${asset}"
  echo "level1: oasdiff not on PATH; provisioning pinned v${OASDIFF_VERSION} to ${BIN_DIR}" >&2
  mkdir -p "${BIN_DIR}"
  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "${tmp}"' RETURN
  if ! curl -fsSL "${url}" -o "${tmp}/oasdiff.tar.gz"; then
    fail_tool "failed to download oasdiff from ${url}"
  fi
  tar -xzf "${tmp}/oasdiff.tar.gz" -C "${tmp}" oasdiff
  install -m 0755 "${tmp}/oasdiff" "${local_bin}"
  echo "${local_bin}"
}

# --- Resolve PROVIDER_SPEC to a local file ---------------------------------
PROVIDER_SPEC="${PROVIDER_SPEC:-}"
[ -n "${PROVIDER_SPEC}" ] || skip "PROVIDER_SPEC is unset"

PROVIDER_LOCAL=""
CLEANUP_PROVIDER=""
case "${PROVIDER_SPEC}" in
  http://*|https://*)
    PROVIDER_LOCAL="$(mktemp)"
    CLEANUP_PROVIDER="${PROVIDER_LOCAL}"
    if ! curl -fsSL "${PROVIDER_SPEC}" -o "${PROVIDER_LOCAL}"; then
      rm -f "${PROVIDER_LOCAL}"
      skip "PROVIDER_SPEC URL unreachable: ${PROVIDER_SPEC}"
    fi ;;
  *)
    [ -f "${PROVIDER_SPEC}" ] || skip "PROVIDER_SPEC path not found: ${PROVIDER_SPEC}"
    PROVIDER_LOCAL="${PROVIDER_SPEC}" ;;
esac
[ -z "${CLEANUP_PROVIDER}" ] || trap 'rm -f "${CLEANUP_PROVIDER}"' EXIT

[ -f "${CONSUMER_SPEC}" ] || fail_tool "consumer spec not found: ${CONSUMER_SPEC}"

OASDIFF="$(resolve_oasdiff)"

echo "=== Level-1 static spec diff (oasdiff v${OASDIFF_VERSION}) ==="
echo "consumer (base): ${CONSUMER_SPEC}"
echo "provider (revision): ${PROVIDER_SPEC}"
echo

# Human-readable changelog of all differences (consumer -> provider).
"${OASDIFF}" diff "${CONSUMER_SPEC}" "${PROVIDER_LOCAL}" || true
echo
echo "--- breaking-change check (consumer as base) ---"
# `breaking` exits non-zero when breaking changes exist; that is the gate.
if "${OASDIFF}" breaking "${CONSUMER_SPEC}" "${PROVIDER_LOCAL}"; then
  echo "level1: PASS — no breaking differences between consumer and provider specs."
  exit 0
else
  echo "level1: breaking differences reported above (consumer vs provider)."
  exit 1
fi
