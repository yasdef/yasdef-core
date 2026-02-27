# Step plan (golden example)

# Step Plan: 1.6b - Example Step Title
Date: 2026-02-09
Planner model/session: gpt-5.2 (planner), session=<fill>
Execution model/session (intended): gpt-5.3-codex (executor), session=<fill>

## Target Bullets
- Add idempotency enforcement for market close command. (SP=3) [REQ-12.1]
- Add integration test coverage for duplicate Idempotency-Key behavior. (SP=1) [REQ-12.1]

## Design Anchor (scope source of truth)
- Feature design: `ai/step_designs/step-1.6b-design.md`
- Scope contract lives in design sections: `## Goal`, `## In Scope`, `## Out of Scope`

## Requirement Tags
- REQ-12.1

## Preconditions / Dependencies
- Review `ai/blocker_log.md` and `ai/open_questions.md` for Step 1.6b.
- Confirm the existing idempotency key persistence strategy for commands.

## Applicable UR Shortlist
- UR-0004 - avoid single-field wrappers; this step touches response shape and could accidentally introduce wrapper DTOs.
- UR-0011 - avoid `Optional` parameters in method signatures while adding validator/service method changes.

## Plan (ordered)
- 1. Locate existing idempotent command patterns (service + repository); align implementation.
- 2. Add/adjust validator so it runs before any writes.
- 3. Implement ledger append + projection update with exactly-once semantics.
- 4. Add integration test for duplicate key, verify no double-apply.
- 5. Update docs/artifacts if any public API behavior changed.

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
