#!/usr/bin/env python3
"""Level-2 dynamic-conformance runner for the Discover Pod consumer contract.

Invoked by `make level2`. Runs schemathesis against a live backend using the
consumer OpenAPI as the contract, then partitions the result against the
committed expected-failures manifest:

  - EXPECTED deviations (path + failing check both listed in the manifest) are
    REPORTED, not build-failing — they are the documented V1 provider gaps
    (DATA-2026-0071 / 0073 / 0074).
  - Any UNEXPECTED failure or error (including an unreachable backend or a
    schema-load error) fails the build with a non-zero exit.

The schemathesis base-URL trap: the consumer spec's `servers` url is the shell
proxy prefix `/api/landvault`, but the backend serves `/areal/...` at its root.
We therefore pass `-u BACKEND_URL` so paths resolve directly against the backend;
without it every request 404s. Auth is supplied via BACKEND_AUTH as an explicit
Basic Authorization header — the consumer spec intentionally declares no
securityScheme (auth is a transport concern carried by the env var, not the
contract).

Env vars (level2 only):
  BACKEND_URL   required — root URL of the running backend
                (e.g. https://landvault-api.staging.miraterrasoil.com)
  BACKEND_AUTH  required — Basic Auth credentials "user:password"
                (password from the STAGING_API_PASSWORD secret)

Exit codes:
  0  — backend conformant, or only expected deviations observed
  1  — at least one UNEXPECTED failure/error (real conformance break)
  2  — usage / configuration error (missing env, missing files, tooling)
"""

from __future__ import annotations

import base64
import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path

import yaml

HERE = Path(__file__).resolve().parent
CONSUMER_SPEC = HERE.parent / "consumer-openapi.yaml"
MANIFEST = HERE / "expected-failures.yaml"

# schemathesis checks we run. response_schema_conformance is the load-bearing
# one for this contract (the V1 divergences are value-level under conformant
# shapes); the others guard against gross breaks (5xx, wrong content type).
CHECKS = "not_a_server_error,status_code_conformance,content_type_conformance,response_schema_conformance"


def die(code: int, msg: str) -> None:
    print(f"level2: {msg}", file=sys.stderr)
    sys.exit(code)


def load_manifest() -> dict[str, set[str]]:
    """Return {templated_path: {expected failing check names}} from the manifest."""
    if not MANIFEST.exists():
        die(2, f"expected-failures manifest not found: {MANIFEST}")
    data = yaml.safe_load(MANIFEST.read_text())
    expected: dict[str, set[str]] = {}
    for entry in data.get("expected_failures", []):
        path = entry.get("path")
        checks = set(entry.get("checks", []))
        if not path:
            continue
        expected.setdefault(path, set()).update(checks)
    if not expected:
        die(2, "manifest has no expected_failures entries")
    return expected


def path_from_label(label: str) -> str:
    """schemathesis scenario label is 'METHOD /templated/path' -> return the path."""
    parts = label.split(" ", 1)
    return parts[1] if len(parts) == 2 else label


def failing_checks(recorder: dict) -> set[str]:
    """Collect the names of failing checks across a scenario's interactions."""
    names: set[str] = set()
    interactions = recorder.get("interactions") or {}
    values = interactions.values() if isinstance(interactions, dict) else interactions
    for interaction in values:
        if not isinstance(interaction, dict):
            continue
        for check in interaction.get("checks") or []:
            if isinstance(check, dict) and check.get("status") in ("failure", "error"):
                name = check.get("name")
                if name:
                    names.add(name)
    return names


def run_schemathesis(backend_url: str, auth_header: str, ndjson_path: Path) -> int:
    """Run schemathesis; return its process exit code. Events land in ndjson_path."""
    cmd = [
        "uv", "run", "--project", str(HERE),
        "schemathesis", "run", str(CONSUMER_SPEC),
        "-u", backend_url,
        "--checks", CHECKS,
        "--continue-on-failure",
        "--header", f"Authorization: {auth_header}",
        "--report", "ndjson",
        "--report-ndjson-path", str(ndjson_path),
        "--phases", "fuzzing,examples",
        "--warnings", "off",
        "-w", "1",
    ]
    print(f"level2: running schemathesis against {backend_url}", file=sys.stderr)
    proc = subprocess.run(cmd)
    return proc.returncode


def classify(ndjson_path: Path, expected: dict[str, set[str]]) -> tuple[list, list]:
    """Partition scenario outcomes into (expected_deviations, unexpected_failures)."""
    expected_hits: list[tuple[str, set[str]]] = []
    unexpected: list[tuple[str, str, set[str]]] = []
    if not ndjson_path.exists():
        return expected_hits, [("<none>", "schemathesis produced no report", set())]

    for line in ndjson_path.read_text().splitlines():
        line = line.strip()
        if not line:
            continue
        event = json.loads(line)
        kind = next(iter(event))
        payload = event[kind]

        if kind == "ScenarioFinished":
            status = payload.get("status")
            if status in ("success", "skip"):
                continue
            recorder = payload.get("recorder") or {}
            label = recorder.get("label") or "<unknown>"
            path = path_from_label(label)
            if status == "error":
                # transport/generation error — never an expected deviation
                unexpected.append((label, "scenario error", set()))
                continue
            # status == "failure": check-level partition
            checks = failing_checks(recorder)
            allowed = expected.get(path)
            if allowed is not None and (not checks or checks <= allowed):
                expected_hits.append((label, checks))
            else:
                unmatched = checks - (allowed or set())
                unexpected.append((label, "unexpected failing checks", unmatched or checks))

        elif kind == "NonFatalError":
            # schema-load failure, connection error, etc. — always real.
            label = payload.get("label") or "<engine>"
            unexpected.append((label, "non-fatal error (e.g. unreachable / load error)", set()))

    return expected_hits, unexpected


def main() -> int:
    backend_url = os.environ.get("BACKEND_URL", "").strip()
    backend_auth = os.environ.get("BACKEND_AUTH", "").strip()
    if not backend_url:
        die(2, "BACKEND_URL is required for level2 (root URL of the running backend)")
    if not backend_auth:
        die(2, "BACKEND_AUTH is required for level2 (Basic Auth 'user:password')")
    if not CONSUMER_SPEC.exists():
        die(2, f"consumer spec not found: {CONSUMER_SPEC}")

    auth_header = "Basic " + base64.b64encode(backend_auth.encode()).decode()
    expected = load_manifest()

    with tempfile.TemporaryDirectory() as tmp:
        ndjson_path = Path(tmp) / "events.ndjson"
        run_schemathesis(backend_url, auth_header, ndjson_path)
        expected_hits, unexpected = classify(ndjson_path, expected)

    print("\n=== Level-2 dynamic conformance (schemathesis) ===\n")
    if expected_hits:
        print(f"EXPECTED V1 deviations (reported, not build-failing) — {len(expected_hits)}:")
        for label, checks in expected_hits:
            chk = ", ".join(sorted(checks)) if checks else "operation-level"
            print(f"  - {label}  [{chk}]")
        print()
    if unexpected:
        print(f"UNEXPECTED failures/errors (build-failing) — {len(unexpected)}:")
        for label, reason, checks in unexpected:
            chk = (": " + ", ".join(sorted(checks))) if checks else ""
            print(f"  - {label}  ({reason}{chk})")
        print("\nlevel2: FAIL — unexpected conformance break(s) above.")
        return 1

    print("level2: PASS — backend conformant or only documented V1 deviations observed.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
