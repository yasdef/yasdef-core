# Capability: ai-audit-review-disposition-gate

## Purpose
Define the shared disposition-completeness gate that controls ai_audit completion and post_review entry.

## Requirements

### Requirement: Shared helper SHALL validate ai_audit review disposition completeness
The workflow SHALL provide a shared helper under `ai/scripts/helpers/` that validates disposition completeness for `ai/step_review_results/review_result-<step>.md` using standard shell exit semantics. The helper MUST require the `## Disposition (per issue)` section, MUST count listed issues only from `## Critical`, `## High`, `## Medium`, and `## Low` severity sections while excluding `- (none)`, and MUST require at least one `- **Accepted**:` or `- **Rejected**:` entry for each counted issue.

#### Scenario: Helper passes when every listed issue has a disposition
- **WHEN** the review artifact contains one or more counted issues and the disposition section contains at least the same number of Accepted/Rejected bullets
- **THEN** the helper exits `0`

#### Scenario: Helper fails when disposition section is missing
- **WHEN** the review artifact omits `## Disposition (per issue)`
- **THEN** the helper exits non-zero and emits a clear readiness failure message

#### Scenario: Helper fails when disposition count is insufficient
- **WHEN** the review artifact lists counted issues across severity sections but has fewer Accepted/Rejected bullets than counted issues
- **THEN** the helper exits non-zero and emits a clear readiness failure message

### Requirement: ai_audit SHALL run the shared helper before completion
`ai/scripts/ai_audit.sh` MUST run the shared review disposition helper as an end-of-phase post-check before emitting the exact ai_audit completion line.

#### Scenario: ai_audit completes only after helper success
- **WHEN** ai_audit finishes its review write-up and the shared helper exits `0`
- **THEN** ai_audit may emit the canonical completion line

#### Scenario: ai_audit stays incomplete when helper fails
- **WHEN** ai_audit finishes its review write-up and the shared helper exits non-zero
- **THEN** ai_audit does not emit the canonical completion line
- **THEN** ai_audit instructs the operator to complete review dispositions before retrying completion

### Requirement: post_review SHALL enforce the same disposition gate before starting
`ai/scripts/post_review.sh` MUST run the shared review disposition helper before post-review consolidation work or history updates.

#### Scenario: post_review proceeds only after shared helper success
- **WHEN** post_review starts for a step and the shared helper exits `0`
- **THEN** post_review may continue into consolidation and history-update logic

#### Scenario: post_review fails fast when shared helper fails
- **WHEN** post_review starts for a step and the shared helper exits non-zero
- **THEN** post_review exits before history consolidation or other post-review output updates
- **THEN** it emits a clear message that ai_audit dispositions were not finished correctly

### Requirement: Process documentation SHALL define the AI Audit Disposition Gate
`ai/AI_DEVELOPMENT_PROCESS.md` MUST document a dedicated AI Audit Disposition Gate that tells ai_audit to rerun or finish dispositions when the helper fails, and tells post_review to require the same helper before starting.

#### Scenario: ai_audit disposition gate is documented
- **WHEN** operators or agents read the ai_audit section of `ai/AI_DEVELOPMENT_PROCESS.md`
- **THEN** they can see that the completion line is blocked until the shared disposition helper passes

#### Scenario: post_review preflight is documented
- **WHEN** operators or agents read post-ai_audit workflow guidance in `ai/AI_DEVELOPMENT_PROCESS.md`
- **THEN** they can see that post_review requires the same helper to pass before starting
