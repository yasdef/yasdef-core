# Step plan template

This file is the template for `ai/step_plans/step-<step>.md`.

Notes:
- Keep the plan concise and execution-focused: ordered steps, constraints, decisions, tests, and artifacts to update.
- Do not restate scope in this artifact. `## Goal`, `## In Scope`, and `## Out of Scope` live in the feature design and are the scope contract.
- Planning completion gate: do not consider planning finished while any open questions remain for the step; resolve/close them (and record durable decisions in `ai/decisions.md`) before finishing planning.
- Planning completion gate: every item from design `## Things to Decide (for final planning discussion)` (or `## Things to Decide`) must have an explicit outcome in `## Decisions Needed` (`Accepted`, `Deferred`, or `Blocked`).
- If a planning-time decision prompt is needed to resolve unclear/blocking choices, ask exactly two numbered options (`1.` recommended/default, `2.` alternative), each with short rationale. User should be able to reply with only `1` or `2`.
- `## Applicable UR Shortlist` accepts only two canonical forms: exact `- None.` or bullets that include `UR-xxxx` IDs (optional rationale). When using UR IDs, prioritize to 3-8 items (max 8).
- Implementation contract: `## Plan (ordered)` is the primary execution checklist for implementation phase.
- Review contract: `## Target Bullets` is the Section 5 user-review checklist to confirm scope completion.

---

# Step Plan: <step> - <step title>
Date: <YYYY-MM-DD>
Planner model/session: <fill>
Execution model/session (intended): <fill>

## Target Bullets
- <bullet text>

## Design Anchor (scope source of truth)
- Feature design: `ai/step_designs/step-<step>-design.md`
- Scope contract lives in design sections: `## Goal`, `## In Scope`, `## Out of Scope`
- If scope changes, update the feature design first, then update this step plan.

## Requirement Tags
- <REQ tags from ai/implementation_plan.md (or (none))>

## Preconditions / Dependencies
- Review `ai/blocker_log.md` and `ai/open_questions.md` for the current step.
- <missing prerequisites or required decisions>

## Applicable UR Shortlist
- None.

## Plan (ordered)
- 1. <subtask, concrete outcome>
- 2. <subtask, concrete outcome>

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
