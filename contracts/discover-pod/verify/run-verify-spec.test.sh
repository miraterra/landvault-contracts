#!/usr/bin/env bash
#
# Self-test for verify-consumer-openapi.mjs (CCT-2026-0011).
#
# WHY THIS EXISTS: verify-spec is the contract-authoring FIDELITY self-check — it
# proves consumer-openapi.yaml faithfully encodes SPEC.md. Wiring it into CI is
# only half the job: without a COMMITTED red-path exercising the *failing* path,
# the gate could silently rot into a false green (the same trap CCT-2026-0010
# caught for level1). This self-test is that committed, repeatable regression
# guard. Run it with `make verify-spec-selftest` or directly.
#
# It drives the verifier DIRECTLY against a committed fixture under testdata/
# (NOT via `make verify-spec`, which targets the real, passing consumer spec)
# and asserts both the exit code AND the content of the output:
#
#   missing-source-enum.yaml → exit 1 (FAIL) AND the output NAMES the specific
#                              C3-source-enum business assertion. The fixture is
#                              a structurally-valid OpenAPI 3.1 copy of the real
#                              consumer spec with ONE real SPEC-fidelity defect:
#                              SourceParam.enum drops `both` (SPEC §3.8 requires
#                              measured|predicted|both).
#
# CONTENT ASSERTION IS LOAD-BEARING (mirrors run-level1.test.sh, validator finding
# from CCT-2026-0010): exit!=0 alone is NOT proof of red-on-DRIFT — the verifier
# also exits 1 on a corrupt/unparseable file (a C0-parse failure). So this test
# additionally asserts that the failure is the SEMANTIC C3-source-enum check AND
# that the structural floor still holds (C0-parse / C0-deref both PASS). A red
# that comes from C0-parse or C0-deref fails this self-test for the WRONG reason
# and is reported as such — it is not a valid red-on-fidelity-drift.
#
# Exit: 0 if all assertions pass; 1 if any assertion fails.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERIFIER="${SCRIPT_DIR}/verify-consumer-openapi.mjs"
TESTDATA="${SCRIPT_DIR}/testdata"
FIXTURE="${TESTDATA}/missing-source-enum.yaml"

failures=0

pass() { echo "  PASS: $*"; }
fail() { echo "  FAIL: $*"; failures=$((failures + 1)); }

echo "=== verify-spec self-test (CCT-2026-0011 fidelity red-path regression guard) ==="

# --- pre-flight: fixture must exist ------------------------------------------
[ -f "${FIXTURE}" ] || { echo "MISSING FIXTURE: ${FIXTURE}"; exit 2; }

# Invoke the verifier DIRECTLY against the fixture (NOT `make verify-spec`).
out="$(node "${VERIFIER}" "${FIXTURE}" 2>&1)"
rc=$?

echo "[case] missing-source-enum fixture → expect exit 1 (FAIL) AND C3-source-enum named"

# --- exit-code assertion -----------------------------------------------------
if [ "${rc}" -eq 0 ]; then
  fail "expected non-zero exit (fidelity drift), got 0 — verifier did NOT catch the defect"
elif [ "${rc}" -eq 1 ]; then
  pass "exit 1 as expected (gate FAILS on SPEC-fidelity drift)"
else
  # rc 2 = missing dep / fatal; rc 3 = target not found. Wrong-reason red.
  fail "verifier exited ${rc} (fatal/usage error, not a check FAIL) — NOT a valid red-on-drift"
fi

# --- content assertion: the SEMANTIC check that must fail --------------------
# Exit!=0 alone is insufficient (a corrupt spec also exits 1 via C0-parse). The
# red must come from the C3-source-enum business assertion.
if echo "${out}" | grep -q "^FAIL  C3-source-enum"; then
  pass "output names the failed business assertion C3-source-enum"
else
  fail "output did not name FAIL C3-source-enum — exit code alone is not proof of red-on-drift"
fi

# --- structural floor must still hold (proves DRIFT, not corruption) ---------
# If the fixture failed to parse or dereference, the red would be a parse-class
# failure (the wrong kind). Assert C0-parse and C0-deref both PASS.
if echo "${out}" | grep -q "^PASS  C0-parse"; then
  pass "C0-parse PASS — fixture is structurally parseable (red is drift, not corruption)"
else
  fail "C0-parse did not PASS — fixture is corrupt; red is parse-class, not fidelity drift"
fi
if echo "${out}" | grep -q "^PASS  C0-deref"; then
  pass "C0-deref PASS — fixture fully dereferences (no broken \$ref)"
else
  fail "C0-deref did not PASS — a broken \$ref would be the wrong kind of red"
fi

# --- Summary ------------------------------------------------------------------
echo "=== self-test summary ==="
if [ "${failures}" -eq 0 ]; then
  echo "ALL ASSERTIONS PASSED"
  exit 0
else
  echo "${failures} ASSERTION(S) FAILED"
  exit 1
fi
