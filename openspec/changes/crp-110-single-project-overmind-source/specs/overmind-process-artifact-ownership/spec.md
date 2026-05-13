## MODIFIED Requirements

### Requirement: Coordinator planning artifacts are owned under overmind
The project SHALL treat `overmind/implementation_plan.md` and `overmind/reqirements_ears.md` as worker runtime planning artifacts. In default orchestrator mode these files SHALL be synchronized runtime copies sourced from the selected feature artifacts located directly under the bound single ASDLC project repo (i.e., `<project-repo>/<feature-id>/implementation_plan.md` and `<project-repo>/<feature-id>/requirements_ears.md`), and in standalone mode they SHALL be treated as direct runtime inputs.

#### Scenario: Default mode refreshes runtime copies from selected feature
- **WHEN** orchestrator runs without `--standalone` for a selected feature under the bound project repo
- **THEN** it reads `implementation_plan.md` and `requirements_ears.md` from `<project-repo>/<feature-id>/`
- **AND** it mirrors them into local `overmind/implementation_plan.md` and `overmind/reqirements_ears.md`
- **AND** worker phases consume those local synchronized runtime copies

#### Scenario: Standalone mode consumes local runtime files directly
- **WHEN** orchestrator runs with `--standalone`
- **THEN** it uses existing local `overmind/implementation_plan.md` and `overmind/reqirements_ears.md` as direct runtime inputs
- **AND** it does not require `<project-repo>/<feature-id>/implementation_plan.md` or `<project-repo>/<feature-id>/requirements_ears.md` to be reachable

#### Scenario: Multi-project source layout is no longer accepted
- **WHEN** orchestrator resolves source artifact paths in default mode
- **THEN** it derives them as `<project-repo>/<feature-id>/...` directly from `overmind_source_path`
- **AND** it does not attempt to read `<source>/projects/<project-id>/<feature-id>/...` or `<source>/<project-id>/<feature-id>/...`

#### Scenario: Legacy ai path is still present during migration
- **WHEN** legacy copies exist under `/ai`
- **THEN** `/overmind` paths remain the source of truth for worker runtime behavior

### Requirement: Documentation reflects coordinator-worker artifact boundary
Project documentation SHALL state that default orchestrator runs read and copy `<project-repo>/<feature-id>/implementation_plan.md` and `<project-repo>/<feature-id>/requirements_ears.md` from the bound single ASDLC project repo into local `/overmind`, and SHALL state that `--standalone` bypasses that flow and uses local `/overmind` files directly.

#### Scenario: Runbook describes single-project source paths
- **WHEN** README documents orchestrator execution
- **THEN** section `5` and the **Main process artifacts** section reference source paths as `<project-repo>/<feature-id>/implementation_plan.md` and `<project-repo>/<feature-id>/requirements_ears.md`
- **AND** they do not reference a `projects/<project-id>/` wrapper segment

#### Scenario: Runbook describes standalone workaround and default behavior
- **WHEN** README documents orchestrator execution
- **THEN** section `5.1` explains when to use `--standalone` and its constraints
- **AND** section `7` states that default runs attempt single-project ASDLC read/copy first while `--standalone` immediately uses local `/overmind` artifacts
