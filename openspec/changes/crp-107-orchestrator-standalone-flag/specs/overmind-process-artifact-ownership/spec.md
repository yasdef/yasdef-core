## MODIFIED Requirements

### Requirement: Coordinator planning artifacts are owned under overmind
The project SHALL treat `overmind/implementation_plan.md` and `overmind/reqirements_ears.md` as worker runtime planning artifacts. In default orchestrator mode these files SHALL be synchronized runtime copies sourced from selected ASDLC feature artifacts, and in standalone mode they SHALL be treated as direct runtime inputs.

#### Scenario: Default mode refreshes runtime copies from selected feature
- **WHEN** orchestrator runs without `--standalone` for a selected ASDLC feature
- **THEN** it reads `implementation_plan.md` and `requirements_ears.md` from that selected feature
- **AND** it mirrors them into local `overmind/implementation_plan.md` and `overmind/reqirements_ears.md`
- **AND** worker phases consume those local synchronized runtime copies

#### Scenario: Standalone mode consumes local runtime files directly
- **WHEN** orchestrator runs with `--standalone`
- **THEN** it uses existing local `overmind/implementation_plan.md` and `overmind/reqirements_ears.md` as direct runtime inputs
- **AND** it does not require `projects/<project-id>/<feature-id>/implementation_plan.md` or `projects/<project-id>/<feature-id>/requirements_ears.md` to be reachable

#### Scenario: Legacy ai path is still present during migration
- **WHEN** legacy copies exist under `/ai`
- **THEN** `/overmind` paths remain the source of truth for worker runtime behavior

### Requirement: Documentation reflects coordinator-worker artifact boundary
Project documentation SHALL state that default orchestrator runs try to read and copy `projects/<project-id>/<feature-id>/implementation_plan.md` and `projects/<project-id>/<feature-id>/requirements_ears.md` into local `/overmind`, and SHALL state that `--standalone` bypasses that flow and uses local `/overmind` files directly.

#### Scenario: Runbook describes standalone workaround and default behavior
- **WHEN** README documents orchestrator execution
- **THEN** section `5.1` explains when to use `--standalone` and its constraints
- **AND** section `7` states that default runs attempt ASDLC read/copy first while `--standalone` immediately uses local `/overmind` artifacts
