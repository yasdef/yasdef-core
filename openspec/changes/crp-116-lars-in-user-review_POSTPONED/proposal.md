## Why

Implementation already treats in-scope linked artifacts as source-of-truth inputs when a translated functional requirement references a `LAR-NNN`, but the pre-dialogue `user_review` self-check does not explicitly re-check the changed behavior against those same artifact links. That leaves a gap: a step can pass implementation readiness with correct ordered-plan closure while still drifting from a linked prototype, schema, or contract in the specific behavior the step touched.

This change should close that gap without changing the phase-state model. `## Plan (ordered)` must remain the only `user_review` phase-state contract. `## Linked Artifacts (in scope)` should act only as a correctness cross-check during the self-review pass before talking to the user.

## What Changes

- Extend the Section 5 `user_review` self-check workflow so that when the step plan contains a non-empty `## Linked Artifacts (in scope)` block, the reviewer fetches those linked artifact locators before opening the review dialogue.
- Define the user-review LAR check as scope-limited and non-hard:
  - it checks only behavior/details the current step actually changed or relied on,
  - it does not require implementing untouched parts of a larger prototype,
  - it does not replace `## Plan (ordered)` as the execution/state contract.
- Define `drift` narrowly for this phase: drift means the current-step implementation contradicts or misimplements artifact-backed details for in-scope touched behavior; broader differences between the implementation and unimplemented parts of the linked artifact are not drift.
- Require the self-check to fix clear, objective linked-artifact drift before asking the user for review, then rerun relevant verification.
- When linked content is ambiguous, unavailable, or the mismatch is not clearly actionable, require user_review to avoid hard-failing the phase and instead surface the concern in the `Review Brief` as a focused hotspot/question.
- Update the `ai_user_review.sh` prompt packet so it includes the step plan `## Linked Artifacts (in scope)` section when present and instructs the model to perform this scoped drift check before dialogue with the user.
- Keep empty or absent step-plan LAR sections as a no-op so existing `user_review` behavior is unchanged for steps without linked artifacts.

## Capabilities

### New Capabilities

- `user-review-linked-artifact-drift-self-check`: User Review phase performs a pre-dialogue linked-artifact fetch-and-compare pass for non-empty step-plan `## Linked Artifacts (in scope)` sections, limited to implementation details touched by the current step, and fixes clear objective drift before requesting user feedback.

### Modified Capabilities

- `orchestrator-user-review-phase`: User Review SHALL keep `## Plan (ordered)` as its only phase-state contract while also using step-plan linked artifacts as a non-hard correctness cross-check during self-review.
- `review-brief-output`: When linked-artifact content is ambiguous, unavailable, or reveals a non-obvious mismatch that is not safe to auto-fix, the Review Brief SHALL surface that item as a targeted hotspot/question before asking the user for feedback.
- `step-plan-ordered-execution`: Step plans MAY carry a `## Linked Artifacts (in scope)` section that informs user-review correctness checks without becoming a second execution checklist or completion gate.

## Impact

- Affected process docs:
  - `ai/AI_DEVELOPMENT_PROCESS.md` Section 5 (`user_review`)
- Affected prompt-generation script:
  - `ai/scripts/ai_user_review.sh`
- Affected tests:
  - `tests/ai_scripts/user_review_phase_tests.sh`
- Prompt-contract impact:
  - user_review prompt should include the linked-artifact block when present,
  - prompt should instruct a pre-dialogue fetch-and-compare self-check,
  - prompt should explicitly preserve `## Plan (ordered)` as the only phase-state source,
  - prompt should describe the linked-artifact check as non-hard and scope-limited.
