## ADDED Requirements

### Requirement: User Review SHALL perform a pre-dialogue linked-artifact self-check when the step plan carries in-scope linked artifacts
When `ai/step_plans/step-<N>.md` contains a non-empty `## Linked Artifacts (in scope)` section, the User Review phase MUST fetch and use those linked artifacts during the pre-dialogue self-check before requesting user feedback.

#### Scenario: Non-empty linked-artifact section triggers the self-check
- **WHEN** User Review starts for a step whose step plan contains one or more `- LAR-NNN | <type> | <title> | <locator>` entries under `## Linked Artifacts (in scope)`
- **THEN** the pre-dialogue self-check fetches those locators before asking the user for the next review item

#### Scenario: Empty or absent linked-artifact section is a no-op
- **WHEN** User Review starts for a step whose step plan omits `## Linked Artifacts (in scope)` or emits it empty
- **THEN** no linked-artifact fetch-and-compare work is required
- **THEN** the rest of the User Review self-check proceeds unchanged

### Requirement: Linked-artifact drift SHALL be defined only for touched current-step behavior
For the User Review self-check, linked-artifact drift MUST mean that the current-step implementation contradicts or misimplements artifact-backed details for behavior the step changed or directly relied on. Untouched or out-of-scope parts of a larger linked artifact MUST NOT be treated as drift.

#### Scenario: Touched implementation contradicts the linked artifact
- **WHEN** the current step changed a behavior or detail that is represented in an in-scope linked artifact
- **AND** the implementation contradicts that linked source in a concrete, current-scope way
- **THEN** the mismatch is treated as linked-artifact drift

#### Scenario: Linked artifact contains extra untouched scope
- **WHEN** an in-scope linked artifact contains additional screens, states, fields, or details that the current step did not change and did not need to rely on
- **THEN** those untouched differences are not treated as linked-artifact drift

### Requirement: Clear linked-artifact drift SHALL be fixed before review dialogue, while ambiguous cases SHALL be surfaced in the Review Brief
The User Review self-check MUST fix clear, objective linked-artifact drift before asking the user for review and MUST rerun relevant verification after the fix. If the linked source is ambiguous, unavailable, or the mismatch is not clearly actionable, User Review MUST NOT hard-fail the phase and MUST instead surface the concern in the Review Brief as a focused hotspot or question.

#### Scenario: Clear objective drift is auto-fixed before asking the user
- **WHEN** the self-check finds a linked-artifact mismatch that is concrete, current-scope, and safe to correct without new user decisions
- **THEN** User Review fixes the implementation before requesting user feedback
- **THEN** User Review reruns relevant verification for the fix

#### Scenario: Ambiguous or unavailable linked content does not hard-fail User Review
- **WHEN** the self-check cannot confidently resolve the linked-artifact mismatch because the content is ambiguous, unavailable, or would require a new user decision
- **THEN** User Review does not block on a new hard gate
- **THEN** the Review Brief calls out the concern as a targeted hotspot or question before asking the user for feedback

