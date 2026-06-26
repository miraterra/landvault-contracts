# landvault-contracts — conformance test runner
#
# The Makefile is the single unifying interface over a deliberately POLYGLOT
# toolchain (CCT-2026-0007): each level uses the best-in-class tool for its job.
#
#   make verify-spec  — Node acceptance verifier: does consumer-openapi.yaml
#                       faithfully encode SPEC.md? (spec-vs-SPEC.md)
#   make level1       — oasdiff static diff: consumer spec vs PROVIDER_SPEC.
#   make level2       — schemathesis dynamic conformance: consumer spec vs a
#                       running backend.
#   make test         — runs all three, AGGREGATING results (each level's exit
#                       code is collected; a per-level summary prints; exit is
#                       non-zero if ANY level failed). Levels are NOT
#                       &&-short-circuited — an early failure never hides later
#                       levels. Each level stays independently invokable.
#
# Per-level env vars (see README "Environment variables"):
#   BACKEND_URL    level2 only — root URL of the running backend.
#   BACKEND_AUTH   level2 only — Basic Auth "user:password" (pwd: STAGING_API_PASSWORD).
#   PROVIDER_SPEC  level1 only — URL or filesystem path to the provider OpenAPI.
# verify-spec needs none.
#
# Three runtimes: Node (verify-spec), the oasdiff Go binary (level1),
# Python-via-uv (level2). See the README for ADR framing (ADR-0066 levels;
# ADR-0061/0062 execution independence).

VERIFY_DIR     := contracts/discover-pod/verify
LEVEL1         := contracts/discover-pod/level1/run-level1.sh
LEVEL1_SELFTEST := contracts/discover-pod/level1/run-level1.test.sh
LEVEL2_DIR     := contracts/discover-pod/level2

.PHONY: help verify-spec level1 level1-selftest level2 test

help:
	@echo "Targets:"
	@echo "  make verify-spec     Node acceptance verifier (spec vs SPEC.md)"
	@echo "  make level1          oasdiff static diff (consumer vs PROVIDER_SPEC)"
	@echo "  make level1-selftest regression guard for the level1 fail policy (committed fixtures)"
	@echo "  make level2          schemathesis dynamic conformance (vs BACKEND_URL)"
	@echo "  make test            run all three, aggregate, exit non-zero if any failed"

# --- verify-spec (Node) ----------------------------------------------------
# `npm ci` installs from the checked-in lockfile so the run is reproducible on
# a clean checkout / in CI.
verify-spec:
	@cd $(VERIFY_DIR) && npm ci --silent && node verify-consumer-openapi.mjs

# --- level1 (oasdiff Go binary) --------------------------------------------
level1:
	@$(LEVEL1)

# --- level1-selftest (fail-policy regression guard, CCT-2026-0010) ----------
# Drives run-level1.sh against committed fixtures under level1/testdata/ and
# asserts the gate is honest: conforming -> exit 0; WARN-only -> exit 0 with
# WARN surfaced; provider-main-0e44479 (breaking) -> exit 1 naming the regions
# break. This guards against re-introducing the FALSE GREEN.
level1-selftest:
	@$(LEVEL1_SELFTEST)

# --- level2 (schemathesis via uv) ------------------------------------------
# uv resolves the pinned environment from level2/uv.lock on first run.
level2:
	@cd $(LEVEL2_DIR) && uv run --project . python run-level2.py

# --- test (aggregate all three; do NOT short-circuit) ----------------------
# Each level runs regardless of earlier outcomes; exit codes are collected and
# summarised; the aggregate exit is non-zero if any level failed.
test:
	@echo "=== landvault-contracts conformance suite ==="
	@rc_verify=0; rc_l1=0; rc_l2=0; \
	echo "\n>>> verify-spec"; ( cd $(VERIFY_DIR) && npm ci --silent && node verify-consumer-openapi.mjs ) || rc_verify=$$?; \
	echo "\n>>> level1";      $(LEVEL1) || rc_l1=$$?; \
	echo "\n>>> level2";      ( cd $(LEVEL2_DIR) && uv run --project . python run-level2.py ) || rc_l2=$$?; \
	echo "\n=== summary ==="; \
	echo "  verify-spec : exit $$rc_verify"; \
	echo "  level1      : exit $$rc_l1 (3 = SKIPPED: PROVIDER_SPEC unset/unreachable)"; \
	echo "  level2      : exit $$rc_l2"; \
	if [ $$rc_verify -ne 0 ] || [ $$rc_l1 -ne 0 ] || [ $$rc_l2 -ne 0 ]; then \
	  echo "\nSUITE: FAIL (one or more levels non-zero)"; exit 1; \
	else \
	  echo "\nSUITE: PASS"; \
	fi
