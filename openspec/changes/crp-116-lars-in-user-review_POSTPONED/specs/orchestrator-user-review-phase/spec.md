## ADDED Requirements

### Requirement: user_review prompt packet SHALL include step-plan linked artifacts when present
When the step plan carries a non-empty `## Linked Artifacts (in scope)` section, `ai/scripts/ai_user_review.sh` MUST include that section in the User Review prompt packet and MUST instruct the model to use it during the pre-dialogue self-check.

#### Scenario: Prompt packet includes linked-artifact context for LAR-backed steps
- **WHEN** `ai/scripts/ai_user_review.sh` builds a prompt for a step whose step plan contains one or more linked-artifact entries
- **THEN** the prompt packet contains the step plan `## Linked Artifacts (in scope)` block
- **THEN** the prompt packet instructs the model to perform the linked-artifact self-check before requesting user feedback

#### Scenario: Prompt packet stays unchanged for steps without linked artifacts
- **WHEN** `ai/scripts/ai_user_review.sh` builds a prompt for a step whose step plan has no linked-artifact entries
- **THEN** the prompt packet may omit the linked-artifact block entirely
- **THEN** no linked-artifact self-check instruction is required

### Requirement: user_review SHALL preserve ordered-plan phase state while using linked artifacts as a non-hard correctness check
User Review MUST keep `## Plan (ordered)` as its only phase-state source even when linked artifacts are present. The linked-artifact check MUST be described as a correctness cross-check only and MUST NOT become a second execution checklist or readiness gate.

#### Scenario: Prompt preserves ordered-plan phase-state contract
- **WHEN** the User Review prompt is generated for a step with linked artifacts
- **THEN** it still states that `## Plan (ordered)` is the only phase-state source
- **THEN** it describes linked artifacts as a correctness cross-check rather than as phase-state authority

