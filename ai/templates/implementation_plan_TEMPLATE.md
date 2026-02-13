# Implementation Plan - Template

Purpose: define a step-only plan (no phases) with clear scope, ordering, and estimation. This template is optimized for AI authorship and review.
Inputs required: EARS-formatted requirements (e.g., `reqirements_ears.md`) must be available and referenced in the plan.

## Conventions
- Steps are ordered to minimize gaps and rework.
- Each step is broken into logically distinct bullets with clear outcomes.
- Each bullet is independently testable and has a single responsibility.
- Step sizes are balanced and kept small.
- Use the estimation rules below.
- The "Plan and discuss the step" and "Review step implementation" bullets are mandatory in every step.
- Always include requirement tags per step (e.g., `[REQ-6] [REQ-7] [REQ-4]`).

## Estimation Convention
- Use SP values: {1, 2, 3, 5, 8}.
- Append `(SP=...)` to every bullet.
- After each step header, add `Est. step total: <N> SP`.
- Target step size: 10–20 SP total per step. Split steps if they exceed 20 SP.

## How to Create Steps and Bullets
1. **Identify prerequisites**: schema, APIs, validators, errors, auth, projections, tests.
2. **Order steps to minimize gaps**:
   - Foundation first (schema, constraints, projections).
   - Command validators before command handlers.
   - Command handlers before read models that depend on them.
   - API changes before client-facing docs/tests that validate them.
3. **Slice steps evenly**:
   - Prefer 3–5 bullets per step.
   - Avoid “mega steps” that exceed 20 SP.
   - If a step is <10 SP, merge it with adjacent work unless it is a hard dependency boundary.
4. **Make bullets logically distinct**:
   - Each bullet should have a single outcome and clear done criteria.
   - Avoid mixing schema + service + tests in a single bullet unless tightly coupled.
   - If a bullet needs multiple layers (schema + service + tests), split into adjacent bullets.
5. **Define verification**:
   - Ensure each bullet implies specific tests or checks.
   - Add doc updates only when behavior changes.
6. **Minimize gaps**:
   - Prefer adding small prerequisite bullets in the current step to avoid blockers later.

## Plan Structure
### Step <X.Y> <Step title> [REQ-6] [REQ-7] [REQ-4]
Est. step total: <N> SP
- [ ] Plan and discuss the step (SP=1) (mandatory)
- [ ] <Bullet 1 outcome> (SP=...)
- [ ] <Bullet 2 outcome> (SP=...)
- [ ] <Bullet 3 outcome> (SP=...)
- [ ] Review step implementation (SP=...) (mandatory)
