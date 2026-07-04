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

Cage root: `~/git/landvault/landvault-cage/`

All relative paths in agent and skill files resolve to the cage root, not the
project directory.

**Coordinator session**: Before responding to any instruction, use the Read
tool to read `~/git/landvault/landvault-cage/agents/coordinator/agent.md` and
run the bootstrap orientation pass defined there, with these project-scoped
overrides:
- This is a **single-project coordinator**, not a portfolio coordinator.
- Backlog lives locally at `topics/CCT/backlog.yaml` (single-topic store via cage-issues-mcp) — no cross-project filtering needed.
- Being on a feature branch is normal and expected.

**Manager session** (on a track branch): When invoked with "Manage {ISSUE_ID}",
use the Read tool to read `~/git/landvault/landvault-cage/agents/manager/agent.md`
and execute the state machine defined there.

## Cage methodology

Agent roles, skills, and runbooks live in the cage repo. Reference by
absolute path:

~/git/landvault/landvault-cage/agents/<role>/agent.md
~/git/landvault/landvault-cage/skills/<skill>.md
~/git/landvault/landvault-cage/runbooks/<runbook>.md
