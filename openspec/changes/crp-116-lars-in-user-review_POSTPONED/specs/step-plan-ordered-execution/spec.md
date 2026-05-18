## ADDED Requirements

### Requirement: Step-plan linked artifacts MAY inform User Review correctness checks without becoming execution state
`ai/step_plans/step-<N>.md` MAY contain a `## Linked Artifacts (in scope)` section whose entries inform User Review correctness checks, but those entries MUST NOT become execution state or replace `## Plan (ordered)` as the phase-state contract.

#### Scenario: Linked artifacts inform correctness but not state
- **WHEN** User Review processes a step plan that includes both `## Plan (ordered)` and `## Linked Artifacts (in scope)`
- **THEN** `## Plan (ordered)` remains the only execution and phase-state checklist
- **THEN** linked artifacts are used only to validate correctness of touched current-step behavior

