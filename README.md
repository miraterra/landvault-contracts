# landvault-contracts

Independent contract package for the LandVault platform.

Consumer OpenAPI artifacts, REQ-tagged schemas, and coverage matrices live here — authored by the consumer side and owned independently of both consumer and provider (ADR-0057).

## Structure

```
Makefile                 # runner entrypoint: verify-spec / level1 / level2 / test
contracts/
  discover-pod/          # Discover Pod ↔ mt-landvault-api boundary
    consumer-openapi.yaml  # Consumer-required OpenAPI 3.1 (derived from SPEC.md)
    coverage-matrix.md     # §8 REQ-* coverage tracking
    verify/                # Level: spec-acceptance (Node)
      verify-consumer-openapi.mjs  # asserts the spec encodes SPEC.md
      package.json / package-lock.json
    level1/                # Level-1: static spec diff (oasdiff)
      run-level1.sh
    level2/                # Level-2: dynamic conformance (schemathesis via uv)
      run-level2.py
      pyproject.toml / uv.lock
      expected-failures.yaml  # known V1 deviations (authoritative gate)
```

## Running the conformance suite

This package is not just an artifact — it is an executable conformance suite.
One command, given a backend URL and credentials, runs the verification levels
and reports results. The tool choice (oasdiff, schemathesis) is encapsulated
here; CI pipelines in the shell (SHELL-2026-0701) and the provider
(DATA-2026-0068) invoke the runner — they do not own the test logic.

| Target            | What it checks                                                  | Runtime         |
|-------------------|-----------------------------------------------------------------|-----------------|
| `make verify-spec`| The consumer spec faithfully encodes SPEC.md (spec-acceptance)  | Node            |
| `make level1`     | Consumer spec vs PROVIDER spec (static diff — ADR-0066 level 1) | oasdiff Go binary |
| `make level2`     | Consumer spec vs a running backend (dynamic — ADR-0066 level 2) | Python via `uv` |
| `make test`       | All three, aggregated (see below)                               | all three       |

The two levels are the ADR-0066 two-level model: **level 1** is the static
spec-vs-spec diff; **level 2** is dynamic conformance against a live backend.
`verify-spec` is a third, distinct check — it proves the *consumer spec itself*
encodes the normative SPEC.md, upstream of both levels.

`make test` **aggregates**: it runs all three regardless of earlier outcomes,
prints a per-level exit-code summary, and exits non-zero if any level failed.
It does not `&&`-short-circuit, so an early failure never hides a later level.
Each level stays independently invokable.

### Polyglot toolchain (deliberate)

There is no single-language tool that covers all three well, so each level uses
its best-in-class tool: `verify-spec` is Node, `level1` is the oasdiff Go binary
(no runtime), `level2` is Python-native schemathesis run via `uv`. The Makefile
is the single unifying interface over the three runtimes. Do not rewrite one in
another's language.

- **Node** (`verify-spec`): `npm ci` installs `js-yaml` + `@apidevtools/swagger-parser`
  from the checked-in lockfile.
- **oasdiff** (`level1`): if not on `PATH`, `run-level1.sh` downloads a **pinned
  v1.20.0** to a repo-local `bin/` (gitignored) — acquisition is deterministic,
  not ad hoc.
- **Python via uv** (`level2`): `uv run` resolves the pinned environment
  (`schemathesis==4.21.10`) from `level2/uv.lock`.

### Environment variables

| Variable        | Required by | Format / example                                                     |
|-----------------|-------------|----------------------------------------------------------------------|
| `BACKEND_URL`   | level2 only | Root URL of the running backend, e.g. `https://landvault-api.staging.miraterrasoil.com` |
| `BACKEND_AUTH`  | level2 only | Basic Auth `user:password` (password from the `STAGING_API_PASSWORD` secret) |
| `PROVIDER_SPEC` | level1 only | A URL **or** a filesystem path to the provider OpenAPI (`http(s)://` is fetched; else treated as a path) |

`verify-spec` needs no env vars. `level1` diffs two documents and needs no
running backend; `level2` requires one.

**Auth is a transport concern, not a contract concern.** The consumer spec
intentionally declares no `securityScheme` and only a relative `server` URL
(the shell proxy prefix `/api/landvault`). `level2` therefore passes
`BACKEND_URL` as the schemathesis base-URL override and injects `BACKEND_AUTH`
as an explicit Basic `Authorization` header — the **env vars, not the spec**,
carry the server location and credentials.

> **base-URL trap (level2):** the consumer spec's `servers` url is the shell
> proxy prefix `/api/landvault`, but the backend serves `/areal/...` at its
> root. `level2` passes `-u $BACKEND_URL` so paths resolve directly; without
> the override every request 404s.

### Interim provider spec (level1)

Until provider PR #80 merges, point `PROVIDER_SPEC` at the provider OpenAPI on
branch `data-2026-spec-conformance-v3` of `mt-landvault-api`. This is the
default interim source; re-point at provider `main` once #80 merges:

```sh
git -C ~/git/landvault/mt-landvault-api show \
  data-2026-spec-conformance-v3:mt-landvault-api/docs/openapi.yaml \
  > /tmp/provider-openapi.yaml
PROVIDER_SPEC=/tmp/provider-openapi.yaml make level1
```

If `PROVIDER_SPEC` is unset or unreachable, `level1` does **not** exit 0 — it
emits a SKIPPED / non-conformant banner and exits with a distinct sentinel
(exit 3), so a missing provider spec is never mistaken for "the specs agree".

### Expected level-2 failures (known V1 deviations)

`level2/expected-failures.yaml` enumerates the documented V1 provider deviations
(keyed to **DATA-2026-0071 / DATA-2026-0073 / DATA-2026-0074**, sourced from
`mt-landvault-api/docs/divergences/`). `make level2` **reports** these without
failing the build, and exits non-zero **only** on an *unexpected* failure. This
manifest — not a CI flag — is the **authoritative gate semantic**, so the
provider CI (DATA-2026-0068) can later drop any transitional `|| true` wrapper
once DATA-2026-0076 lands and rely on this file to discriminate known-vs-real.

The manifest is **v3-branch-derived and pending re-confirmation** when PR #80
merges (it mirrors the level1 readiness note): re-verify the deviation set
against provider `main` at that point.

### Current status

| Level         | Readiness                                                                 |
|---------------|---------------------------------------------------------------------------|
| `verify-spec` | **Green today** — passes against the merged consumer spec.                |
| `level2`      | **Green today** — runs against staging; only failures are the manifest's. |
| `level1`      | Exercisable today against the v3-branch provider spec; **fully green only when provider PR #80 merges** and `PROVIDER_SPEC` points at provider `main`. |

### ADR framing

The boundary under test is `mt-landvault-api` acting as a **BFF** for the
Discover Pod — a consumer-driven boundary. The runner's value rests on:

- **ADR-0066** — the three-artifact / two-level model that defines level 1
  (static spec diff) and level 2 (dynamic conformance). Cited above where the
  levels are explained.
- **ADR-0061** — execution independence: this contract package is independently
  *executable*, not merely independently authored. Authorship and execution
  independence are orthogonal axes.
- **ADR-0062** — the shell, as integrator-steward, is accountable for the level-1
  gate passing; it fulfils that accountability by *invoking* this runner in CI,
  not by owning the test code.

This is **not** an ADR-0057 Platform-Steward data-product contract: ADR-0057's
scope excludes consumer-driven boundaries (BFFs). ADR-0057 applies only to the
*package shape* (one independently-owned package, conformance-suite face), not
to the boundary's stewardship class.

## Governing documents

- Normative source: `landvault-shell/docs/data-layer-maps/SPEC.md`
- ADR-0056..0062 and ADR-0066 in `landvault-governance/`
- Initiative: `landvault-management/projects/contract-conformance-testing/`
