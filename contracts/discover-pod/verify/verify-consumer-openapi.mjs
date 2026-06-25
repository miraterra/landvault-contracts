#!/usr/bin/env node
/**
 * Independent acceptance verifier for SHELL-2026-0698.
 *
 * Authored by the Test Author from SPEC.md (landvault-shell/docs/data-layer-maps/SPEC.md)
 * ALONE — it has not seen the implementer's OpenAPI document. It encodes what the
 * consumer-required OpenAPI 3.1 contract MUST satisfy, derived solely from the SPEC
 * and the issue's what_to_resolve.
 *
 * Target document (default): ../consumer-openapi.yaml
 *
 * Run (reproducible — package.json + package-lock.json are checked in here):
 *   cd landvault-contracts/contracts/discover-pod/verify
 *   npm ci                                 # installs js-yaml + swagger-parser from lockfile
 *   node verify-consumer-openapi.mjs [path-to-openapi.yaml]
 *
 * Or from the repo root: `make verify-spec`.
 *
 * Exit code 0 = all checks pass. Non-zero = at least one FAIL.
 *
 * NOTE ON OPENAPI 3.1 + swagger-parser: @apidevtools/swagger-parser validates
 * 3.0 strictly; for 3.1 it dereferences/parses but its strict schema validation
 * may not fully cover 3.1. We therefore use it only to PARSE + RESOLVE $refs, and
 * assert OpenAPI-3.1 structural rules ourselves. If swagger-parser is unavailable,
 * the script falls back to js-yaml parse only (the 3.1.x version assertion and all
 * structural checks still run; only deep $ref resolution is skipped).
 */

import { readFileSync, existsSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';

const __dirname = dirname(fileURLToPath(import.meta.url));
const target = process.argv[2]
  ? resolve(process.argv[2])
  : resolve(__dirname, '..', 'consumer-openapi.yaml');

let YAML;
try {
  const mod = await import('js-yaml');
  YAML = mod.default ?? mod; // js-yaml exposes named exports under ESM (no default)
} catch {
  console.error('FATAL: js-yaml not installed. Run: npm install --no-save js-yaml @apidevtools/swagger-parser');
  process.exit(2);
}

const results = [];
const pass = (id, msg) => results.push({ id, ok: true, msg });
const fail = (id, msg) => results.push({ id, ok: false, msg });
const check = (id, cond, msg) => (cond ? pass(id, msg) : fail(id, msg));

// ---------------------------------------------------------------------------
// C0 — File present & parses
// ---------------------------------------------------------------------------
if (!existsSync(target)) {
  console.error(`FATAL: target document not found: ${target}`);
  console.error('(Expected once SHELL-2026-0698 produces the OpenAPI file.)');
  process.exit(3);
}
let doc;
try {
  doc = YAML.load(readFileSync(target, 'utf8'));
  pass('C0-parse', `Document parses as YAML: ${target}`);
} catch (e) {
  fail('C0-parse', `Document does NOT parse as YAML: ${e.message}`);
  report();
  process.exit(1);
}

// Optionally validate/dereference with swagger-parser (best-effort, non-fatal).
let dereferenced = doc;
try {
  const spMod = await import('@apidevtools/swagger-parser');
  const SwaggerParser = spMod.default ?? spMod;
  dereferenced = await SwaggerParser.dereference(JSON.parse(JSON.stringify(doc)));
  pass('C0-deref', 'swagger-parser dereferenced all $refs (no broken references)');
} catch (e) {
  fail('C0-deref', `swagger-parser could not dereference/validate: ${e.message}`);
}

// ---------------------------------------------------------------------------
// C1 — Valid OpenAPI 3.1: declares openapi: 3.1.x
// ---------------------------------------------------------------------------
const ver = String(doc?.openapi ?? '');
check('C1-openapi-3.1', /^3\.1\.\d+$/.test(ver), `openapi version is 3.1.x (found: "${ver}")`);
check('C1-info', !!doc?.info?.title && !!doc?.info?.version, 'info.title and info.version present');
check('C1-paths', doc?.paths && typeof doc.paths === 'object', 'paths object present');

const paths = doc?.paths ?? {};

// helper: find an operation by method + path (path matched literally; {param}
// names may differ in the doc, so we normalise {anything} -> {} for comparison).
const normPath = (p) => p.replace(/\{[^}]+\}/g, '{}');
const pathIndex = {};
for (const [p, item] of Object.entries(paths)) {
  for (const m of ['get', 'post', 'put', 'patch', 'delete']) {
    if (item && item[m]) pathIndex[`${m.toUpperCase()} ${normPath(p)}`] = { rawPath: p, op: item[m] };
  }
}
const findOp = (method, specPath) => pathIndex[`${method} ${normPath(specPath)}`];

// ---------------------------------------------------------------------------
// C2 — Every SPEC §3 endpoint present with correct method + path
//      (independently enumerated from SPEC §3.0 endpoint table + §3.7 + §3.8)
// ---------------------------------------------------------------------------
const ENDPOINTS = [
  { method: 'GET',  path: '/areal',                       req: 'REQ-META',        spec: '§3.1' },
  { method: 'GET',  path: '/areal/regions',               req: null,              spec: '§3.0 (geometry/PMTiles)' },
  { method: 'GET',  path: '/areal/analytes/{analyteId}',  req: 'REQ-AGG/REQ-PRED', spec: '§3.2/§3.3/§3.8' },
  { method: 'GET',  path: '/areal/suitability',           req: 'REQ-RULE-RESULT', spec: '§3.4' },
  { method: 'GET',  path: '/areal/histograms/{analyteId}', req: 'REQ-HIST',       spec: '§3.7' },
];

for (const e of ENDPOINTS) {
  const found = findOp(e.method, e.path);
  check(`C2 ${e.method} ${e.path}`, !!found, `${e.method} ${e.path} present (${e.spec})`);
}

// Negative: the old file-distribution endpoint and the OUT-OF-SCOPE FarmSample
// MUST NOT be modelled as consumer-required operations.
const allOpPaths = Object.keys(paths).map(normPath);
check('C2-no-legacy-areal',
  !allOpPaths.some((p) => p === '/api/landvault/areal'),
  'legacy file-distribution GET /api/landvault/areal NOT present (it is a different endpoint, §3.0)');
check('C2-no-farmsample',
  !Object.keys(paths).some((p) => /farm|sample/i.test(p)),
  'no own-FarmSample endpoint present (§3.5 OUT OF SCOPE)');

// ---------------------------------------------------------------------------
// C3 — source parameter on the analytes endpoint (§3.8)
// ---------------------------------------------------------------------------
{
  const op = findOp('GET', '/areal/analytes/{analyteId}');
  if (op) {
    const params = collectParams(paths, op.rawPath, op.op);
    const sourceParam = params.find((p) => p.name === 'source');
    check('C3-source-param', !!sourceParam, 'GET /areal/analytes/{id} declares a `source` query parameter (§3.8)');
    if (sourceParam) {
      const sch = sourceParam.schema?.$ref ? resolveRef(sourceParam.schema.$ref) : sourceParam.schema;
      const en = sch?.enum ?? [];
      const need = ['measured', 'predicted', 'both'];
      check('C3-source-enum',
        need.every((v) => en.includes(v)),
        `source enum includes measured|predicted|both (found: ${JSON.stringify(en)})`);
    }
  } else {
    fail('C3-source-param', 'analytes endpoint missing; cannot check source param');
  }
}

// ---------------------------------------------------------------------------
// C4 — §4 empty / suppressed / error states represented
//   No data (record absent)           -> empty array / absent member is representable
//   Not enough data                   -> suppressed:true + reason 'insufficient-data'
//   Match-count suppressed            -> suppressed:true + reason 'match-count-below-threshold'
//   Zero match                        -> density:0 (suitability), not suppressed
// We assert these tokens appear in the document text (schema enums / descriptions),
// since exact schema placement is an implementer choice. Token presence in the
// serialized doc is the consumer-observable requirement.
// ---------------------------------------------------------------------------
const docText = readFileSync(target, 'utf8');
const STATE_TOKENS = [
  { id: 'C4-suppressed', token: /\bsuppressed\b/, label: '`suppressed` flag present (§4 / REQ-STATE-2)' },
  { id: 'C4-reason-insufficient', token: /insufficient-data/, label: "reason 'insufficient-data' present (§4 Not-enough-data)" },
  { id: 'C4-reason-matchcount', token: /match-count-below-threshold/, label: "reason 'match-count-below-threshold' present (§4 Match-count-suppressed)" },
  { id: 'C4-density', token: /\bdensity\b/, label: '`density` field present (§4 Zero-match / §3.4)' },
];
for (const s of STATE_TOKENS) check(s.id, s.token.test(docText), s.label);

// ---------------------------------------------------------------------------
// C5 — Response envelope (§3.0): contractVersion, generatedAt, query, data
// ---------------------------------------------------------------------------
for (const f of ['contractVersion', 'generatedAt', 'query', 'data']) {
  check(`C5-envelope-${f}`, new RegExp(`\\b${f}\\b`).test(docText),
    `response envelope field \`${f}\` present (§3.0)`);
}

// ---------------------------------------------------------------------------
// C6 — Every operation and every schema component carries a REQ-* tag.
//   The spec instruction: "every operation and schema element citing its source
//   REQ-* tag." We accept the citation in any of: x-req extension, description,
//   tags array, or an externalDocs description on the operation/schema.
// ---------------------------------------------------------------------------
const REQ_RE = /\bREQ-[A-Z][A-Z0-9-]*\b/g;

function citedReqTags(node) {
  if (!node || typeof node !== 'object') return [];
  const blob = [
    node['x-req'], node['x-req-tag'], node['x-reqTags'],
    node.description, node.summary,
    Array.isArray(node.tags) ? node.tags.join(' ') : '',
    node.externalDocs?.description,
  ].filter(Boolean).join(' ');
  return blob.match(REQ_RE) ?? [];
}

let opTotal = 0, opTagged = 0;
const untaggedOps = [];
for (const [p, item] of Object.entries(paths)) {
  for (const m of ['get', 'post', 'put', 'patch', 'delete']) {
    if (item && item[m]) {
      opTotal++;
      if (citedReqTags(item[m]).length > 0) opTagged++;
      else untaggedOps.push(`${m.toUpperCase()} ${p}`);
    }
  }
}
check('C6-ops-tagged', opTotal > 0 && opTagged === opTotal,
  `every operation carries a REQ-* citation (${opTagged}/${opTotal}; untagged: ${JSON.stringify(untaggedOps)})`);

const schemas = doc?.components?.schemas ?? {};
let scTotal = 0, scTagged = 0;
const untaggedSchemas = [];
for (const [name, sch] of Object.entries(schemas)) {
  scTotal++;
  if (citedReqTags(sch).length > 0) scTagged++;
  else untaggedSchemas.push(name);
}
check('C6-schemas-tagged', scTotal > 0 && scTagged === scTotal,
  `every schema component carries a REQ-* citation (${scTagged}/${scTotal}; untagged: ${JSON.stringify(untaggedSchemas)})`);

// ---------------------------------------------------------------------------
// C7 — REQ-* tag coverage: the set of REQ tags cited in the document must cover
//   the in-scope REQ-* tags that the consumer contract is responsible for.
//   In-scope contract REQ tags (the ones that name wire-observable shapes/ops):
// ---------------------------------------------------------------------------
const REQUIRED_REQ_TAGS = [
  'REQ-META',        // §3.1 GET /areal
  'REQ-AGG',         // §3.2 measured aggregate record
  'REQ-PRED',        // §3.3 predicted aggregate record
  'REQ-RULE-RESULT', // §3.4 GET /areal/suitability
  'REQ-HIST',        // §3.7 GET /areal/histograms/{id}
  'REQ-STATE-1',     // §4 distinct empty/suppressed states
  'REQ-STATE-2',     // §4 render suppressed without statistics
];
// OUT OF SCOPE for the consumer wire contract (UI/render/colour requirements,
// own-farm, framework gaps) — NOT expected in this OpenAPI:
const OUT_OF_SCOPE_REQ_TAGS = [
  'REQ-CHORO-1','REQ-CHORO-2','REQ-CHORO-3','REQ-CTRL-1','REQ-CTRL-2',
  'REQ-ABS-1','REQ-COLOR-1','REQ-BM-1','REQ-BM-2','REQ-BM-3',
  'REQ-RULE-1','REQ-RULE-2','REQ-RULE-3','REQ-RULE-4','REQ-RULE-5',
  'REQ-WT-1','REQ-WT-2','REQ-WT-3',
  'REQ-PRED-1','REQ-PRED-2','REQ-PRED-3','REQ-PRED-4','REQ-PRED-5',
  'REQ-POP-1','REQ-POP-2','REQ-HIST-1','REQ-HIST-2','REQ-VIS-1',
];
const citedAll = new Set((docText.match(REQ_RE) ?? []));
const missing = REQUIRED_REQ_TAGS.filter((t) => !citedAll.has(t));
check('C7-req-coverage', missing.length === 0,
  `all in-scope REQ tags cited somewhere in the document (missing: ${JSON.stringify(missing)})`);

// Informational: report any REQ tag cited that is UI-only out-of-scope (allowed,
// but flagged so the reviewer can sanity-check the document isn't over-modelling).
const overModelled = [...citedAll].filter((t) => OUT_OF_SCOPE_REQ_TAGS.includes(t));
if (overModelled.length) {
  pass('C7-info-oos', `INFO: document also cites UI/out-of-scope REQ tags (allowed, verify intentional): ${JSON.stringify(overModelled)}`);
}

// ---------------------------------------------------------------------------
// C8 — Schema shapes match SPEC §3 for in-scope records (required fields/types).
//   We search resolved schemas for the required-field sets named in the SPEC.
//   These are field-name presence checks against the dereferenced document text,
//   scoped per the record they belong to where a named schema is found.
// ---------------------------------------------------------------------------
const derefText = JSON.stringify(dereferenced);

// §3.1 REQ-META catalogue fields
const META_FIELDS = ['analytes','years','crops','regions','thresholds',
  'benchmarkScalable','filterSteps','valueRange'];
check('C8-meta-fields',
  META_FIELDS.every((f) => new RegExp(`"${f}"`).test(derefText) || new RegExp(`\\b${f}\\b`).test(docText)),
  `§3.1 catalogue fields present (${META_FIELDS.join(', ')})`);

// §3.2 REQ-AGG measured aggregate stat fields
const AGG_FIELDS = ['regionId','suppressed','sampleCount','fieldCount','samplesPerField',
  'mean','stdDev','median','q1','q3','whiskerLow','whiskerHigh'];
check('C8-agg-fields',
  AGG_FIELDS.every((f) => new RegExp(`\\b${f}\\b`).test(docText)),
  `§3.2 measured aggregate fields present (${AGG_FIELDS.join(', ')})`);

// §3.3 REQ-PRED predicted record: has stats, MUST NOT carry sampleCount/fieldCount
// in the predicted schema, MUST NOT carry confidence anywhere (§7-E DECIDED).
const confidenceSchemas = [];
for (const [name, sch] of Object.entries(schemas)) {
  if (sch && typeof sch === 'object') {
    if (sch.properties && Object.prototype.hasOwnProperty.call(sch.properties, 'confidence')) {
      confidenceSchemas.push(`${name}.properties.confidence`);
    }
    if (Array.isArray(sch.required) && sch.required.includes('confidence')) {
      confidenceSchemas.push(`${name}.required[confidence]`);
    }
  }
}
check('C8-pred-no-confidence',
  confidenceSchemas.length === 0,
  `§3.3/§7-E: no \`confidence\` field anywhere (removed in v0.2.0) (found: ${JSON.stringify(confidenceSchemas)})`);
// (Negative on sampleCount/fieldCount within predicted is implementer-structure
//  dependent; flagged as a manual review item in the report rather than auto-failed.)

// §3.4 REQ-RULE-RESULT suitability response fields
const RULE_FIELDS = ['ratingThresholds','regions','score','criteria',
  'matchingFields','totalFields','density'];
check('C8-rule-fields',
  RULE_FIELDS.every((f) => new RegExp(`\\b${f}\\b`).test(docText)),
  `§3.4 suitability response fields present (${RULE_FIELDS.join(', ')})`);
// ratingThresholds fixed [0.30,0.70] standard — value presence is informational.
// §3.4 + DATA-2026-0071 (merged PR #1): suitability is a GET (read op). The
// SuitabilityRequest is NOT a POST body — it is carried as a URL-encoded JSON
// `request` query parameter. Assert both: (a) the GET operation declares a
// `request` query param, and (b) the SuitabilityRequest schema shape is present
// (criteria/clauses/weight/step) in components/schemas.
{
  const op = findOp('GET', '/areal/suitability');
  let hasRequestQueryParam = false;
  if (op) {
    const params = collectParams(paths, op.rawPath, op.op);
    hasRequestQueryParam = params.some((p) => p.name === 'request' && p.in === 'query');
  }
  const hasRequestShape =
    /\bclauses\b/.test(docText) && /\bweight\b/.test(docText) && /\bstep\b/.test(docText);
  check('C8-rule-request-criteria',
    hasRequestQueryParam && hasRequestShape,
    '§3.4 suitability is GET with a URL-encoded `request` query param, and the ' +
    'SuitabilityRequest shape (criteria/clauses/weight/step) is present ' +
    `(query-param: ${hasRequestQueryParam}, shape: ${hasRequestShape})`);
}

// §3.7 REQ-HIST histogram response fields
const HIST_FIELDS = ['valueRange','bins','from','to','count'];
check('C8-hist-fields',
  HIST_FIELDS.every((f) => new RegExp(`\\b${f}\\b`).test(docText)),
  `§3.7 histogram response fields present (${HIST_FIELDS.join(', ')})`);

// §3.8 both-mode resolvedSource discriminator
check('C8-resolved-source',
  /\bresolvedSource\b/.test(docText),
  '§3.8 both-mode `resolvedSource` discriminator present');

// §3.6 BenchmarkRef
check('C8-benchmark-ref',
  /\bbenchmarkApplied\b/.test(docText) && (/\bBenchmarkRef\b/.test(docText) || /crop-mlra/.test(docText)),
  '§3.6 BenchmarkRef / benchmarkApplied present');

// ---------------------------------------------------------------------------
function collectParams(allPaths, rawPath, op) {
  const pathItem = allPaths[rawPath] ?? {};
  const merged = [...(pathItem.parameters ?? []), ...(op.parameters ?? [])];
  return merged.map((p) => (p && p.$ref ? resolveRef(p.$ref) : p)).filter(Boolean);
}
function resolveRef(ref) {
  // local refs only: #/components/parameters/Name
  const parts = ref.replace(/^#\//, '').split('/');
  let n = doc;
  for (const part of parts) n = n?.[part];
  return n;
}

function report() {
  const failed = results.filter((r) => !r.ok);
  console.log('\n=== SHELL-2026-0698 consumer-openapi verification ===\n');
  for (const r of results) console.log(`${r.ok ? 'PASS' : 'FAIL'}  ${r.id}  — ${r.msg}`);
  console.log(`\n${results.length - failed.length}/${results.length} checks passed.`);
  if (failed.length) {
    console.log(`\n${failed.length} FAILED:`);
    for (const r of failed) console.log(`  - ${r.id}: ${r.msg}`);
  }
  console.log('\nManual-review items (not auto-asserted):');
  console.log('  M1 §3.3: confirm the PREDICTED schema specifically omits sampleCount/fieldCount');
  console.log('           (S16) while the measured schema includes them.');
  console.log('  M2 §3.4: confirm measured.* is suppressible (suppressed/reason) but predicted.* is not.');
  console.log('  M3 §3.4: confirm ratingThresholds default [0.30, 0.70] (§7-B).');
  console.log('  M4 §3.1: confirm thresholds = {K, M, Kprime} and crops include "general".');
}

report();
const anyFail = results.some((r) => !r.ok);
process.exit(anyFail ? 1 : 0);
