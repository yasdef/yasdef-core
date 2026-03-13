# Step plan (golden example)

# Step Plan: 1.6b - Example Step Title
Date: 2026-02-09
Planner model/session: gpt-5.2 (planner), session=<fill>
Execution model/session (intended): gpt-5.3-codex (executor), session=<fill>

## Design Anchor (scope source of truth)
- Feature design: `ai/step_designs/step-1.6b-design.md`
- Scope contract lives in design sections: `## Target Bullets`, `## Goal`, `## In Scope`, `## Out of Scope`
- Requirement-translation source lives in design section: `## Selected EARS Requirements (for planning translation)`

## Preconditions / Dependencies
- Review `ai/blocker_log.md` and `ai/open_questions.md` for Step 1.6b.
- Confirm the existing idempotency key persistence strategy for commands.

## Applicable UR Shortlist
- UR-0004 - avoid single-field wrappers; this step touches response shape and could accidentally introduce wrapper DTOs.
- UR-0011 - avoid `Optional` parameters in method signatures while adding validator/service method changes.

## Plan (ordered)
- [x] 1. Finalize the three Step 1.8 planning decisions and lock execution scope/contract in this plan.
- [x] 2. Add internal rebuild entrypoint (`POST /internal/v1/projections/rebuild?name=...`) with `Idempotency-Key` header and validator-backed input handling.
- [x] 3. Introduce rebuild persistence primitives: projection-target table truncation, ordered ledger batch read by `event_seq ASC`, and checkpoint CRUD for `projection_checkpoints`.

## Functional Requirements (translated from design EARS)
- [x] FR-1.6b-001 The system SHALL reject duplicate close-command `Idempotency-Key` submissions with a stable conflict error and no second write. EARS[REQ-12.1]
- [x] FR-1.6b-002 The system SHALL return the same conflict semantics for duplicate key replay across retries. EARS[REQ-12.1]

## Architecture / Helper Flow
- Resource → Service (`@Transactional`) → Validator (side-effect free) → Ledger append + projection update (same tx).

## Implementation Notes / Constraints
- Must follow `AGENTS.md` and `ai/AI_DEVELOPMENT_PROCESS.md`.
- Keep diffs minimal; no formatting-only changes.

## Tests
- `src/test/java/.../*IT`: duplicate idempotency key returns stable error code and does not write twice.

## Docs / Artifacts
- `ai/decisions.md`: record any new decision about idempotency strategy (if needed).

## Risks / Edge Cases
- Double-submit during race conditions; ensure DB constraint / repository logic prevents duplicates.

## Assumptions
- Existing idempotency keys are stored per command and validated consistently.

## Decisions Needed
- (none)

## Sources (if any)
- (none)
