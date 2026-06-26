#!/usr/bin/env bash
#
# Self-test for run-level1.sh (CCT-2026-0010).
#
# WHY THIS EXISTS: the Level-1 gate shipped as a FALSE GREEN — it reported PASS
# even on ERROR-level breaking changes — precisely because nothing exercised the
# *failing* path. This self-test is the committed, repeatable regression guard
# for the fail policy. Run it with `make level1-selftest` or directly.
#
# It drives run-level1.sh against three COMMITTED fixtures under testdata/ and
# asserts both the exit code AND the content of the output:
#
#   1. conforming.yaml            → exit 0 (PASS). Conforming spec (derivative of
#                                   the consumer spec) diffs clean against it.
#   2. warn-only.yaml             → exit 0 (PASS) AND the WARN findings (optional
#                                   query-param removals) are SURFACED in the
#                                   output. Enforces "WARN is report-only but
#                                   printed loudly" (ADR-0058) — not just documented.
#   3. provider-main-0e44479.yaml → exit 1 (FAIL) AND the output NAMES the specific
#                                   GET /areal/regions response-body-type ERROR.
#                                   This is the provider main spec pinned to commit
#                                   0e44479 (mt-landvault-api), the same diff shell
#                                   PR #212 runs (consumer contract vs provider main).
#
# CONTENT ASSERTION IS LOAD-BEARING (validator finding, CCT-2026-0010): exit!=0
# alone is NOT a valid proof of red-on-break — a corrupt/empty provider spec also
# exits 1 (it parses as api-path-removed). So the red-path case asserts the run
# fails AND names the `response-body-type-changed` break on /areal/regions.
#
# A runner exit of 2 (oasdiff tooling/usage error) on the red-path case fails the
# self-test for the WRONG reason and is reported as such — it is not treated as a
# valid red-on-break.
#
# Exit: 0 if all cases pass; 1 if any assertion fails.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUNNER="${SCRIPT_DIR}/run-level1.sh"
TESTDATA="${SCRIPT_DIR}/testdata"

CONFORMING="${TESTDATA}/conforming.yaml"
WARN_ONLY="${TESTDATA}/warn-only.yaml"
PROVIDER_MAIN="${TESTDATA}/provider-main-0e44479.yaml"

failures=0

pass() { echo "  PASS: $*"; }
fail() { echo "  FAIL: $*"; failures=$((failures + 1)); }

# run_case <fixture> -> captures output in $out and exit code in $rc
run_case() {
  out="$(PROVIDER_SPEC="$1" bash "${RUNNER}" 2>&1)"
  rc=$?
}

echo "=== run-level1 self-test (CCT-2026-0010 fail-policy regression guard) ==="

# --- pre-flight: fixtures must exist -----------------------------------------
for f in "${CONFORMING}" "${WARN_ONLY}" "${PROVIDER_MAIN}"; do
  [ -f "${f}" ] || { echo "MISSING FIXTURE: ${f}"; exit 2; }
done

# --- Case 1: conforming → exit 0, PASS ---------------------------------------
echo "[case 1] conforming fixture → expect exit 0 (PASS)"
run_case "${CONFORMING}"
if [ "${rc}" -eq 0 ]; then pass "exit 0 as expected"; else fail "expected exit 0, got ${rc}"; fi
if echo "${out}" | grep -q "level1: PASS"; then pass "output reports PASS"; else fail "output did not report PASS"; fi

# --- Case 2: WARN-only → exit 0, PASS, WARN findings surfaced -----------------
echo "[case 2] WARN-only fixture → expect exit 0 (PASS) AND WARN findings printed"
run_case "${WARN_ONLY}"
if [ "${rc}" -eq 0 ]; then pass "exit 0 as expected (WARN is report-only, not gating)"; else fail "expected exit 0, got ${rc}"; fi
if echo "${out}" | grep -q "level1: PASS"; then pass "output reports PASS"; else fail "output did not report PASS"; fi
# WARN must be printed LOUDLY, not suppressed — assert the change id is present.
if echo "${out}" | grep -q "request-parameter-removed"; then
  pass "WARN findings (request-parameter-removed) surfaced in output"
else
  fail "WARN findings NOT surfaced — report-only must still print loudly"
fi

# --- Case 3: provider main 0e44479 → exit 1, FAIL, regions break named --------
echo "[case 3] provider-main-0e44479 fixture → expect exit 1 (FAIL) AND regions break named"
run_case "${PROVIDER_MAIN}"
if [ "${rc}" -eq 2 ]; then
  # Tooling error: this fails the test for the WRONG reason, not red-on-break.
  fail "runner exited 2 (oasdiff tooling/usage error) — NOT a valid red-on-break result"
elif [ "${rc}" -eq 1 ]; then
  pass "exit 1 as expected (gate FAILS on ERROR-level break)"
else
  fail "expected exit 1, got ${rc}"
fi
# CONTENT assertion: the run must NAME the specific GET /areal/regions break.
# Exit!=0 alone is insufficient (a corrupt/empty spec also exits 1).
if echo "${out}" | grep -q "response-body-type-changed"; then
  pass "output names the response-body-type-changed break"
else
  fail "output did not name response-body-type-changed — exit code alone is not proof of red-on-break"
fi
if echo "${out}" | grep -q "/areal/regions"; then
  pass "output names path /areal/regions"
else
  fail "output did not name /areal/regions"
fi

# --- Summary ------------------------------------------------------------------
echo "=== self-test summary ==="
if [ "${failures}" -eq 0 ]; then
  echo "ALL CASES PASSED"
  exit 0
else
  echo "${failures} ASSERTION(S) FAILED"
  exit 1
fi
