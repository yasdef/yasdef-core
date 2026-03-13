# Step plan template

This file is the template for `ai/step_plans/step-<step>.md`.

---

# Step Plan: <step> - <step title>
Date: <YYYY-MM-DD>
Planner model/session: <fill>
Execution model/session (intended): <fill>

## Design Anchor (scope source of truth)
- Feature design: `ai/step_designs/step-<step>-design.md`
- Scope contract lives in design sections: `## Target Bullets`, `## Goal`, `## In Scope`, `## Out of Scope`
- Requirement-translation source lives in design section: `## Selected EARS Requirements (for planning translation)`
- If scope changes, update the feature design first, then update this step plan.

## Preconditions / Dependencies
- Review `ai/blocker_log.md` and `ai/open_questions.md` for the current step.
- <missing prerequisites or required decisions>

## Applicable UR Shortlist
- None.

## Plan (ordered)
- [ ] 1. <subtask, concrete outcome>
- [ ] 2. <subtask, concrete outcome>

## Functional Requirements (translated from design EARS)
- [ ] FR-<step-id>-001 The system SHALL <implementation-specific, testable behavior>. EARS[REQ-<id>]

## Architecture / Helper Flow
- <overview of helper/service design and call flow>

## Implementation Notes / Constraints
- Must follow `AGENTS.md` and `ai/AI_DEVELOPMENT_PROCESS.md`.
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
- <for each design "Things to Decide" item: Accepted/Deferred/Blocked + rationale + follow-up artifact if deferred/blocked>

## Sources (if any)
- <web.run sources or other references>
