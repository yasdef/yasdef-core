## MODIFIED Requirements

### Requirement: Coordinator artifacts SHALL be boundary inputs only
The workflow SHALL treat local `overmind/implementation_plan.md` and `overmind/reqirements_ears.md` on branch `overmind` as direct boundary inputs only after orchestrator has mirrored them from one selected ASDLC feature, and design SHALL not start without a valid mirrored EARS artifact.

#### Scenario: Design consumes mirrored coordinator artifacts directly
- **WHEN** design context is assembled for a step after feature selection
- **THEN** the workflow reads target bullets from mirrored `overmind/implementation_plan.md`
- **AND** it reads selected EARS blocks from mirrored `overmind/reqirements_ears.md`

#### Scenario: ai_audit entry proof-check uses mirrored coordinator targets
- **WHEN** ai_audit executes Section 6.0 entry proof-check for the selected feature
- **THEN** proof status is evaluated against current-step target bullets from mirrored `overmind/implementation_plan.md`

#### Scenario: Design is blocked when mirrored EARS is unavailable
- **WHEN** orchestrator cannot mirror a usable selected-feature `requirements_ears.md` into local `overmind/reqirements_ears.md`
- **THEN** the workflow exits non-zero before design prompt generation
- **AND** `ai_design` does not run
