# Step plan (golden example)

# Step Plan: 1.6b - Example Step Title
Date: 2026-05-25
Planner model/session: gpt-5.2 (planner), session=<fill>
Execution model/session (intended): gpt-5.3-codex (executor), session=<fill>

## Design Anchor (scope source of truth)
- Feature design: `.asdlc_worker/step_designs/step-1.6b-example-step-design.md`
- Scope contract lives in design sections: `## Target Bullets`, `## Goal`, `## In Scope`, `## Out of Scope`
- Requirement-translation source lives in design section: `## Selected EARS Requirements (for planning translation)`

## Preconditions / Dependencies
- Review per-step open questions: `.asdlc_worker/step_open_questions/step-1.6b-example-step-open-questions.md`
- Review per-step blockers: `.asdlc_worker/step_blockers/step-1.6b-example-step-blockers.md`
- Confirm the existing idempotency-key persistence strategy for commands.

## Linked Artifacts (in scope)
- LAR-003 | Figma | Close Command UI Mockup | https://figma.com/file/example/close-command

## Applicable UR Shortlist
- UR-0004 - avoid single-field wrappers; this step touches response shape and could accidentally introduce wrapper DTOs.
- UR-0011 - avoid `Optional` parameters in method signatures while adding validator/service method changes.

## Plan (ordered)
- [x] 1. Finalize the remaining planning decisions and lock the execution scope in this plan.
- [x] 2. Add the internal rebuild entrypoint with validator-backed input handling and stable duplicate-key semantics.
- [x] 3. Introduce rebuild persistence primitives and checkpoint handling in the same transaction boundary.

## Functional Requirements (translated from design EARS)
- [x] FR-1.6b-001 The system SHALL reject duplicate close-command `Idempotency-Key` submissions with a stable conflict error and no second write. EARS[REQ-12.1]
- [x] FR-1.6b-002 The system SHALL return the same conflict semantics for duplicate key replay across retries. EARS[REQ-12.2]

## Architecture / Helper Flow
- Resource -> Service (`@Transactional`) -> Validator (side-effect free) -> Ledger append + projection update (same transaction).

## Implementation Notes / Constraints
- Must follow `AGENTS.md`.
- Keep diffs minimal; no formatting-only changes.

## Tests
- `src/test/java/.../*IT`: duplicate idempotency key returns stable error code and does not write twice.

## Docs / Artifacts
- `.asdlc_worker/decisions.md`: record any new decision about idempotency strategy if planning resolves one.

## Risks / Edge Cases
- Double-submit during race conditions; ensure repository logic prevents duplicate acceptance.

## Assumptions
- Existing idempotency keys are stored per command and validated consistently.

## Decisions Needed
- Idempotency persistence strategy | Accepted | Keep the existing per-command persistence model because it matches current transaction boundaries and avoids extra migration work.

## Sources (if any)
- (none)
