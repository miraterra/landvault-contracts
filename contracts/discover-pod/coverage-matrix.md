# Discover Pod consumer-OpenAPI — REQ-* coverage matrix

Tracks how every REQ-* tag and S-item from SPEC.md (`landvault-shell/docs/data-layer-maps/SPEC.md`, v0.2.0-draft.2) maps into `consumer-openapi.yaml`, and records the alignment review (SHELL-2026-0698 t4) against the live shell client `src/api/insights/arealApi.ts` and the dummy server `scripts/areal-dummy-server/`.

Drift control (CCT-2026-0002, Option A): each OpenAPI element carries `x-req` + `x-spec-section`. When SPEC changes a tagged section, the REQ-tag is the join key for surfacing drift here.

---

## 1. Endpoint coverage (SPEC §3 → operations)

| SPEC § | Endpoint | OpenAPI operationId | REQ tag | Status |
|---|---|---|---|---|
| §3.1 | `GET /areal` | `getArealCatalogue` | REQ-META | Covered |
| §3.0 | `GET /areal/regions` (PMTiles) | `getArealRegions` | REQ-META | Covered (binary, no envelope) |
| §3.2/§3.3/§3.8 | `GET /areal/analytes/{analyteId}` | `getArealAnalyte` | REQ-AGG | Covered (source-resolved oneOf) |
| §3.4 | `POST /areal/suitability` | `postArealSuitability` | REQ-RULE-RESULT | Covered |
| §3.7 | `GET /areal/histograms/{analyteId}` | `getArealHistogram` | REQ-HIST | Covered |

All five §3.0 resources are present.

## 2. Schema coverage (SPEC §3 data model → components)

| SPEC § | Schema element | OpenAPI component(s) | REQ tag | Status |
|---|---|---|---|---|
| §3.0 | Response envelope | `Envelope` + per-endpoint `*Envelope` | REQ-META | Covered |
| §3.1 | Dataset catalogue | `CatalogueData`, `AnalyteCatalogueEntry`, `Crop`, `RegionRef`, `SuppressionThresholds`, `ValueRange` | REQ-META | Covered |
| §3.2 | Measured county aggregate | `MeasuredCountyRecord`, `AggregateStats` | REQ-AGG | Covered |
| §3.3 | Predicted county aggregate | `PredictedCountyRecord` | REQ-PRED | Covered (no confidence — §7-E) |
| §3.4 | Suitability req/resp | `SuitabilityRequest`, `Criterion`, `Clause`, `SuitabilityData`, `SuitabilityRegion`, `SuitabilityMeasured`, `SuitabilityPredicted`, `SuitabilityCriterionResult` | REQ-RULE-RESULT | Covered |
| §3.6 | BenchmarkRef | `BenchmarkRef` | REQ-AGG | Covered |
| §3.7 | Histogram | `HistogramData`, `HistogramBin` | REQ-HIST | Covered |
| §3.8 | source param / both | `SourceParam`, `BothCountyRecord` (`resolvedSource`) | REQ-PRED | Covered |
| §3.5 | Own FarmSample | — | — | **OUT OF SCOPE** (S19/S20; §1). Deliberately not modelled. |
| §3.9 | Backend computation table | — | — | Non-wire (server-internal); no schema. Documented in SPEC, nothing to project. |

## 3. §4 state coverage

| SPEC §4 state | Record form | OpenAPI realisation | REQ tag |
|---|---|---|---|
| No data | record absent | absence of a `MeasuredCountyRecord` for the regionId | REQ-STATE |
| Not enough data | `suppressed:true, reason:'insufficient-data'` | `MeasuredCountyRecord` / `SuitabilityMeasured` fields; `EmptySuppressedState` documents it | REQ-STATE |
| Zero match | `density:0` (not suppressed) | `SuitabilityCriterionResult.density`; `EmptySuppressedState.density` | REQ-STATE |
| Match-count suppressed | `suppressed:true, reason:'match-count-below-threshold'` | `SuitabilityMeasured.reason` enum | REQ-STATE |
| Normal | full record | base record schemas | REQ-AGG/REQ-PRED |

`REQ-STATE-1` (hatch vs transparent distinguishable) and `REQ-STATE-2` (suppressed carries no statistic) are encoded by the conditional presence of stat fields and the `reason` enum. Transport-level errors are modelled separately as `ErrorResponse` (not a §4 record state).

## 4. REQ-* tag census

REQ tags that name a **contract wire element** (the scope of an OpenAPI projection) and are addressed in the document:

| REQ tag | SPEC § | Addressed in OpenAPI? |
|---|---|---|
| REQ-META | §3.1 / §3.0 | Yes — catalogue + regions + envelope |
| REQ-AGG | §3.2 | Yes — MeasuredCountyRecord, AggregateStats, BenchmarkRef |
| REQ-PRED (REQ-PRED-3) | §3.3 / §3.8 | Yes — PredictedCountyRecord (no confidence/counts), BothCountyRecord |
| REQ-RULE-RESULT | §3.4 | Yes — full suitability req/resp graph |
| REQ-HIST | §3.7 | Yes — HistogramData/HistogramBin |
| REQ-STATE-1 / REQ-STATE-2 | §4 | Yes — via record-form encoding + EmptySuppressedState |

REQ tags that are **UI / behavioural** requirements (SPEC §5–§6), not wire-contract elements — correctly **out of OpenAPI scope** (an OpenAPI describes the HTTP contract, not frontend rendering). Listed for completeness; their contract dependency is the schema field cited:

| REQ tag | SPEC § | Why not a wire element | Backing field in contract |
|---|---|---|---|
| REQ-CHORO-1/2/3 | §5.1 | map rendering | MeasuredCountyRecord + §4 states |
| REQ-CTRL-1/2 | §5.2 | control population | CatalogueData |
| REQ-ABS-1, REQ-COLOR-1 | §5.3 | colour ramp | ValueRange, SourceParam |
| REQ-BM-1/2/3 | §5.4 | benchmark UI | crop param, BenchmarkRef |
| REQ-RULE-1/2/4/5 | §5.5 | rule UI / colour | filterSteps, Clause, ratingThresholds |
| REQ-RULE-3 | §5.5/§3.4 | dual-source eval | SuitabilityRegion.measured+predicted |
| REQ-WT-1/2/3 | §5.6 | weight UI | Criterion.weight |
| REQ-PRED-1/2/4 | §5.7 | toggle/side-by-side | SourceParam, BothCountyRecord |
| REQ-PRED-5 | §5.7/§3.4 | dual-source eval | SuitabilityRegion |
| REQ-POP-1/2 | §5.8 | popup | MeasuredCountyRecord + PredictedCountyRecord |
| REQ-HIST-1/2 | §5.9 | histogram UI | HistogramData |
| REQ-VIS-1 | §5.10 | transparency | none (pure rendering) |
| REQ-COLOR-1 | amendment | colour | SourceParam |

NFRs: `NFR-VER-1` (version marker + tolerate additive fields) → `Envelope.contractVersion` + additive-field policy. `NFR-PERF-1`, `NFR-MAT-1`, `NFR-A11Y-1` are non-wire.

**Count:** ~40 REQ-* tags in SPEC. 8 are wire-contract tags (REQ-META, REQ-AGG, REQ-PRED/-3, REQ-RULE-RESULT, REQ-HIST, REQ-STATE-1/-2) — all addressed in the OpenAPI. The remaining ~32 are UI/behavioural/NFR tags that an HTTP contract does not project; each is backed by a contract field as listed above. §3.5 (own FarmSample) is the one explicit OUT-OF-SCOPE data shape (S19/S20).

---

## 5. Alignment review (t4) — OpenAPI vs arealApi.ts vs dummy server

SPEC governs the contract. Where the client or fixtures diverge, the divergence is recorded here and the OpenAPI follows SPEC.

### 5.1 Matches (contract and both sources agree)

- **Envelope** `{ contractVersion, generatedAt, query, data }` — `arealApi.ts` `ArealEnvelope<T>` and dummy `envelope()` both match SPEC §3.0. `contractVersion` = `"0.2.0"` in fixtures.
- **Endpoint paths** — client paths (`/api/landvault/areal`, `/areal/analytes/{id}`, `/areal/histograms/{id}` plural, `/areal/suitability`, regions PMTiles) match the SPEC §3.0 table and the dummy router. Histogram path is the corrected plural form (`/histograms/`).
- **Catalogue** `AnalyteCatalogueEntry` — client `ArealAnalyte` and fixture `ANALYTES[]` match SPEC §3.1 field-for-field (id, label, unit, category enum, benchmarkScalable, filterSteps, filterStepsUnit, valueRange tuple). `SuppressionThresholds {K,M,Kprime}` matches `ArealThresholds` and fixture `THRESHOLDS`.
- **Measured record** — fixture `buildMeasuredRecords` emits exactly the §3.2 fields incl. `suppressed`/`reason:'insufficient-data'` and the full stats block. Sub-threshold-fieldCount injection exercises the §4 "not enough data" state.
- **Suitability** — client `ArealSuitability*` types and fixture `buildSuitabilityRecords` match §3.4: per-region nested `measured`/`predicted`, `ratingThresholds:[0.30,0.70]`, per-criterion `{id, matchingFields, totalFields, density}`, `reason` enum incl. `match-count-below-threshold`. `source` param drives which keys appear.
- **Histogram** — client `ArealHistogramData` and fixture `buildHistogram` match §3.7 (`valueRange` + `bins[{from,to,count}]`).
- **source / both** — `BothCountyRecord.resolvedSource` matches fixture `buildBothRecords` (`resolvedSource: 'measured'|'predicted'`) and SPEC §3.8.

### 5.2 Discrepancies (SPEC governs; OpenAPI follows SPEC)

| # | Element | SPEC says | Live source | Disposition in OpenAPI |
|---|---|---|---|---|
| D1 | Predicted record `confidence` | §3.3 / §7-E **DECIDED 2026-06-18**: no confidence in v0.2.0; field removed | **dummy `buildPredictedRecords` STILL emits `confidence`**; `buildBothRecords` emits `confidence:null` on measured | OpenAPI `PredictedCountyRecord` omits `confidence` (SPEC governs). Inline note flags the stale fixture. **Fixture is stale — recommend a follow-up to drop it.** Client `arealApi.ts` correctly does NOT carry confidence (aligned with SPEC). |
| D2 | Catalogue `regions` | §3.1 lists `regions: {regionId,name}[]` as a catalogue field; dummy `handleCatalogue` returns it | **client `ArealCatalogueData` OMITS `regions`** (parser ignores it) | OpenAPI `CatalogueData.regions` included as optional (SPEC + fixture have it). Client gap noted inline — client tolerates the extra field (NFR-VER-1) but does not consume it. Not a contract break. |
| D3 | Suitability top-level `summary` | **Not in SPEC §3.4** | **client `ArealSuitabilitySummary` AND dummy `summary{measured?,predicted?}` both present** (SHELL-2026-0678 / S17) | OpenAPI models `summary` as an OPTIONAL additive field (NFR-VER-1) with a note that SPEC §3.4 does not define it. SPEC governs: this is an additive extension the consumer tolerates. **Flag for SPEC reconciliation: either add `summary` to §3.4 or confirm it as consumer-optional.** |
| D4 | Predicted public `fieldCount` | §3.8: predicted MAY carry the county's total `fieldCount` (public), MUST NOT carry sample-derived counts | dummy `buildPredictedRecords` carries neither `sampleCount` nor `fieldCount` | OpenAPI permits optional public `fieldCount` on `BothCountyRecord` per §3.8; `PredictedCountyRecord` omits counts (matches both SPEC MUST-NOT and the fixture). No conflict. |
| D5 | Suitability `predicted` denominator | §3.4: `predicted.totalFields` = all county fields; `measured.totalFields` = fields with samples | fixtures use larger predicted totalFields (50–250) vs measured (10–130) — consistent with the denominator rule | Documented in `SuitabilityPredicted` description. Match. |

### 5.3 Provider-observed transport behaviour (not SPEC §4 record states)

- Dummy server returns HTTP `404 {error,analyteId}` for unknown analyteId, `400 {error}` for malformed suitability body / invalid source. SPEC §4 expresses *record-level* states as record forms, not HTTP errors; the consumer treats absent data as no-data (grey), not as an error. OpenAPI models these as `ErrorResponse` on the `404`/`400` responses, clearly separated from §4 record states. This is an alignment note, not a divergence.

---

## 6. Open items for the review gate (be-review-2)

1. **D1 (confidence):** Confirm the OpenAPI is correct to omit `confidence` per §7-E, and that the stale fixture field is a known follow-up (not a contract requirement). *(Recommendation: omit — SPEC §7-E is DECIDED.)*
2. **D3 (summary):** Decide whether the suitability `summary` block (live in client + fixtures via SHELL-2026-0678) should be promoted into SPEC §3.4, or stay a consumer-optional additive field. The OpenAPI currently models it as optional with a divergence note. *(This is the one genuine SPEC-vs-implementation gap.)*
3. **D2 (catalogue regions):** Confirm `regions` belongs in the catalogue contract (SPEC says yes); the client not consuming it is a client-side gap, not a contract change.
4. **Scope confirmation:** §3.5 own-FarmSample is deliberately absent (OUT OF SCOPE per S19/S20/§1). Confirm no other §3 element was expected.
