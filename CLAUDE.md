# landvault-contracts

The independent contract package for the LandVault platform — consumer OpenAPI
artifacts, REQ-tagged schemas, and coverage matrices for service boundaries.
Contract artifacts in this repo are authored by the consumer side and owned
independently of both consumer and provider, per ADR-0057.

@CLAUDE.local.md

---

## Issue tracking

Issues live in-repo under `topics/CCT/issues/` (cage-issues format).
The MCP server `cage-issues-mcp --root <this repo>` provides agent tooling
(create_issue, update_issue, begin_transaction, commit_task, etc.).

Initiative brief: `~/git/landvault/landvault-management/projects/contract-conformance-testing/initiative-brief.yaml`
Normative source: `~/git/landvault/landvault-shell/docs/data-layer-maps/SPEC.md`
Governing ADRs: ADR-0056..0062 in `~/git/landvault/landvault-governance/`

---

## Agent Roles

This repo is CAGE-scoped: sessions operating under CAGE additionally follow
`CAGE.md` (the generated protocol — see the pointer in AGENTS.md). Sessions
not operating under CAGE ignore both this section and CAGE.md.

Agent definitions and skills ship with the `@dleangen/cage-coordinator`
package (installed as a devDependency of this repo). Base definitions:

    node_modules/@dleangen/cage-coordinator/.claude/agents/<role>/agent.md
    node_modules/@dleangen/cage-coordinator/skills/<skill>.md

Project-specific overrides, when needed, live at the same relative paths
under this repo's `.claude/` and shadow the package versions. Coordinator
sessions are driven by the `cage-coordinator` CLI (the FSM is the source
of truth — `status`, `bootstrap`, `next`, `resume`).

**Coordinator session**: Before responding to any instruction, read the package's
`.claude/agents/coordinator/agent.md` and
run the bootstrap orientation pass defined there, with these project-scoped
overrides:
- This is a **single-project coordinator**, not a portfolio coordinator.
- Backlog lives locally at `topics/CCT/backlog.yaml` (single-topic store via cage-issues-mcp) — no cross-project filtering needed.
- Being on a feature branch is normal and expected.
- Work lands as a **PR to the repo owner**, not a direct merge to main.
  Use `gh pr create` at the landing step instead of `cage-git land --accept`.

**Manager session** (on a track branch): When invoked with "Manage {ISSUE_ID}",
read the package's `.claude/agents/manager/agent.md`
and execute the state machine defined there.

@AGENTS.md
