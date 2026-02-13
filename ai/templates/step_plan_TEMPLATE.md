# Step plan template

This file is the template for `ai/step_plans/step-<step>.md`.

Notes:
- Keep the plan concise and explicit about scope, assumptions, risks, tests, and artifacts to update.
- The `## User Command (manual only - do not execute in assistant)` block is appended/updated by `ai/scripts/ai_plan.sh` and must be preserved.
- Planning completion gate: do not consider planning finished while any open questions remain for the step; resolve/close them (and record durable decisions in `ai/decisions.md`) before finishing planning.

---

# Step Plan: <step> - <step title>
Date: <YYYY-MM-DD>
Planner model/session: <fill>
Execution model/session (intended): <fill>

## Target Bullet
- <bullet text>

## Goal
- <one-sentence outcome>

## In Scope
- <what this step must accomplish>

## Out of Scope
- <explicit non-goals>

## Requirement Tags
- <REQ tags from ai/implementation_plan.md (or (none))>

## Preconditions / Dependencies
- Review `ai/blocker_log.md` and `ai/open_questions.md` for the current step.
- <missing prerequisites or required decisions>

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
- <explicit decisions; mark blockers>

## Sources (if any)
- <web.run sources or other references>
