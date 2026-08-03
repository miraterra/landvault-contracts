<!-- cage:generated:start name="cage-core" version="0.4.0" -->
# AGENTS.md

This file tells AI agents how to work in this project.

## Orientation

Before doing anything, read `README.md` to understand what this project is and what is expected.

## Scope discipline

Work only on what you have been asked to do. If you discover something outside that scope, tell the user and label it:

- `[NEW ISSUE]` — should be tracked and addressed separately
- `[BLOCKING]` — must be resolved before you can continue
- `[DEFER]` — worth noting, not urgent

Never expand scope without explicit user confirmation.

## Before committing

Always show the user what you are about to commit and wait for explicit confirmation before running `git commit`.

## How issues work

Issues are tracked in this project's issue tracker. Here is how communication flows so both sides know what to expect.

### What the maintainers do

When you file an issue:

- **When it is picked up**, you will receive an update: "Now in progress."
- **If they get blocked** or need more time, you will receive a comment explaining why.
- **If they have a question for you**, they will @-mention you in a comment. You will be notified. The @-mention is the signal.
- **When a fix ships**, they will close the issue with a comment that names the version it is included in.

All status changes happen as comments. Labels are silent; comments generate notifications.

### What you should do

- **Watch your notifications.** Every comment on an issue you filed will arrive by email or notification.
- **An @-mention means action is needed from you.** Read the comment and reply in the issue thread.
- **A closed issue means the fix is live.** Check the closing comment for the version number, then update your dependency to pull the change.

## Build modes

A build mode describes how much engineer presence the session requires and what drives pacing. Mode is set in the directive set at session start; it is not inferred from the issue.

### `autonomous`

The system drives end-to-end. The engineer is present only at the bookends: session start (providing the directive set) and session close (visual check, CR adjudication, merge decision). In between, the coordinator auto-advances through non-freeze gates without surfacing intermediate findings. Entry condition: directive set present at session start with `mode: autonomous`.

### `supervised`

The engineer is present throughout the session. The coordinator surfaces each gate and waits for explicit approval before advancing. Default mode for standard work where judgment calls may arise mid-session.

### `guided`

Engineer and Claude co-drive. Used for architectural and exploratory work where design decisions must precede build. The coordinator does not advance past design gates without an explicit design decision from the engineer.

**Classification is not 1:1 with mode.** A well-scoped standard issue with a clean directive set can run autonomously. An architectural issue cannot run autonomously regardless of directive set quality — `architectural` classification forces `guided` as a floor.

## Issue classification

Classification describes the structural complexity of the work, not its difficulty. It determines the default build mode and which validator paths apply.

### `simple`

Narrow scope, known pattern, no cross-system effects, single task or very few tasks. No new interfaces, no shared state changes, no cross-repo impact.

Default mode: **autonomous**

### `standard`

Normal implementation work: multiple tasks, known patterns, isolated effects. The common case for feature work and bug fixes.

Default mode: **supervised** (can run autonomous with a directive set that explicitly sets `mode: autonomous`)

### `architectural`

Open design decisions, shared interfaces, cross-repo effects, or work where the implementation approach itself is uncertain. Cannot run autonomously regardless of directive set.

Default mode: **guided** (floor — cannot be overridden to autonomous)

### `mechanical-refactor`

Structural code change with no new types, no behavior change, and ≤3 tasks. Examples: rename, extract, move, reformat. The validator skip path applies: because the change is mechanical and test-confirmed, validator overhead can be bypassed when the issue is so classified.

Default mode: **supervised** (skip path eligible)

## Change Requests (CRs)

A Change Request is an initiative-level proposal for a spec amendment, filed by an autonomous build session when it discovers a gap between the current spec and what the work actually requires. A CR is a proposal, not a patch — it is never applied during the build. CRs accumulate and are reviewed in bulk at the visual check.

### Format

```yaml
id: CR-YYYY-NNNN
filed_at: <ISO 8601 timestamp>
filed_by: <issue-id>          # which issue dispatch triggered this CR
affects: <path>               # which spec or document would change
description: >
  What the proposed change is.
rationale: >
  What was discovered during the build that prompted this CR.
scope_assessment: within-directive | outside-directive
status: pending               # pending | approved | rejected
resolution: >                 # filled in at visual check adjudication
  Why the CR was approved or rejected.
```

### Location

`.cage/coordinator/change-requests.yaml` — alongside `plan.yaml` and `session-notes.md`. CRs are coordinator-level artifacts scoped to the initiative session.

### Lifecycle

1. **Filed** — an autonomous build session files a CR when a Worker (or the coordinator itself) discovers an initiative-level spec is stale or incomplete.
2. **Surfaced** — if an automated validation session runs after the build, it reads and summarizes pending CRs for the engineer.
3. **Adjudicated** — the engineer approves or rejects each CR at the visual check.
4. **Applied** — approved CRs are incorporated into the relevant spec; rejected CRs are retained with a rejection note in `resolution`.

### CRs vs CAGE issues

A CR is an intra-initiative proposal, not a tracked work item. It does not receive a `CAGE-YYYY-NNNN` ID and does not appear in the issue tracker. It lives in `.cage/coordinator/` and is scoped to the session that produced it. If an approved CR implies follow-on work, that work is filed as a CAGE issue at adjudication time.

### Adjudication is exclusively human

Approving or rejecting a CR is never an agent decision. Not the Worker that filed it, not the Manager, not the Coordinator — no agent adjudicates a CR on its own, even when it is confident the CR is correct, even when the finding later turns out to be correct. Confidence is not authority. Only the engineer adjudicates, and only at the visual check.

Watch for this failure mode: an agent files a CR correctly, then separately reports it as already "adjudicated: approved" — in its own summary, in a downstream issue description, or in a status update — while the CR file on disk still shows `status: pending`. The CR itself was handled correctly; the failure is in the agent's *report*, which claimed a human sign-off that never happened. Treat any claim of CR adjudication that isn't backed by `status` and `resolution` set in `.cage/coordinator/change-requests.yaml` as false until the engineer confirms it.

### Reference implementation

`cage-coordinator` is the first implementation of this spec. Its `cr` subcommands read and write `.cage/coordinator/change-requests.yaml` directly:

```
cage-coordinator cr add --filed-by <issue-id> --affects <path> --description <text> --rationale <text> [--scope within-directive|outside-directive]
cage-coordinator cr list
```

Source: `src/cr.ts` (read/write logic), `src/cli.ts` (subcommand wiring). `cr add` defaults every new entry to `status: pending` and `resolution: ''` — the concrete enforcement of the invariant above. Nothing in the codebase sets `status` to anything else; that field is only ever written by a human at adjudication.
<!-- cage:generated:end name="cage-core" -->
