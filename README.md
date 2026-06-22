# landvault-contracts

Independent contract package for the LandVault platform.

Consumer OpenAPI artifacts, REQ-tagged schemas, and coverage matrices live here — authored by the consumer side and owned independently of both consumer and provider (ADR-0057).

## Structure

```
contracts/
  discover-pod/          # Discover Pod ↔ mt-landvault-api boundary
    consumer-openapi.yaml  # Consumer-required OpenAPI 3.1 (derived from SPEC.md)
    coverage-matrix.md     # §8 REQ-* coverage tracking
```

## Governing documents

- Normative source: `landvault-shell/docs/data-layer-maps/SPEC.md`
- ADR-0056..0062 in `landvault-governance/`
- Initiative: `landvault-management/projects/contract-conformance-testing/`
