# Step plan template

This file is the template for `.asdlc_worker/step_plans/step-<step>-<feature-id>.md`.

---

# Step Plan: <step> - <step title>
Date: <YYYY-MM-DD>
Planner model/session: <fill>
Execution model/session (intended): <fill>

## Design Anchor (scope source of truth)
- Feature design: <design path>
- Scope contract lives in design sections: `## Target Bullets`, `## Goal`, `## In Scope`, `## Out of Scope`
- Requirement-translation source lives in design section: `## Selected EARS Requirements (for planning translation)`
- If scope changes, update the feature design first, then update this step plan.

## Preconditions / Dependencies
- Review per-step open questions: `<open questions path>`
- Review per-step blockers: `<blockers path>`
- <missing prerequisites or required decisions>

## Linked Artifacts (in scope)
- <LAR-NNN | type | title | locator> (omit or leave empty when no LARs are in scope for this step)

## Applicable UR Shortlist
- None.

## Plan (ordered)
- [ ] 1. <subtask, concrete outcome>
- [ ] 2. <subtask, concrete outcome>

## Functional Requirements (translated from design EARS)
- [ ] FR-<step-id>-001 The system SHALL <implementation-specific, testable behavior>. EARS[REQ-<id>]

## Architecture / Helper Flow
- Put execution mechanics here when they matter for implementation invariants.
- <overview of helper/service design and call flow>

## Implementation Notes / Constraints
- Must follow `AGENTS.md`.
- <constraints specific to this step>

## Tests
- <tests to add or update>

## Docs / Artifacts
- <openapi/postman/decisions/blocker_log/plan updates>

## Risks / Edge Cases
- <most likely failure modes>

## Assumptions
- <explicit assumptions>

## Decisions Needed
- <design decision title> | Accepted/Deferred/Blocked | <rationale and follow-up>

## Sources (if any)
- <web.run sources or other references>
