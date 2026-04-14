## ADDED Requirements

### Requirement: Standalone mode bypasses ASDLC artifact flow
The orchestrator SHALL accept `--standalone` and, when set, SHALL skip ASDLC feature discovery, remote source validation, and feature artifact mirroring, using local `overmind/` runtime files directly.

#### Scenario: Standalone mode uses local runtime artifacts
- **WHEN** an operator runs orchestrator with `--standalone`
- **THEN** orchestrator reads step-routing input from `overmind/implementation_plan.md`
- **AND** orchestrator reads design/planning input from `overmind/reqirements_ears.md`
- **AND** orchestrator does not scan `projects/<project-id>/<feature-id>/` to select runtime artifacts

#### Scenario: Standalone mode does not require ASDLC reachability
- **WHEN** orchestrator runs with `--standalone` and ASDLC source paths are unreachable
- **THEN** orchestrator continues by using local `overmind/` runtime files
- **AND** it does not fail solely because remote ASDLC artifact paths are unavailable

#### Scenario: Standalone mode fails fast on missing local runtime inputs
- **WHEN** orchestrator runs with `--standalone` and either `overmind/implementation_plan.md` or `overmind/reqirements_ears.md` is missing
- **THEN** orchestrator exits non-zero with an explicit missing-artifact error
- **AND** it does not enter design or implementation phases

### Requirement: Standalone mode is explicitly visible in logs
The orchestrator SHALL emit explicit operator-facing log messages when standalone mode is active and SHALL identify the local artifact paths used.

#### Scenario: Standalone startup log is emitted
- **WHEN** orchestrator starts with `--standalone`
- **THEN** logs include an explicit standalone-mode marker
- **AND** logs state that ASDLC artifact discovery and mirroring are bypassed
- **AND** logs list `overmind/implementation_plan.md` and `overmind/reqirements_ears.md` as active runtime inputs

### Requirement: Default mode behavior remains unchanged
The orchestrator SHALL preserve existing ASDLC-bound artifact selection and mirroring behavior when `--standalone` is not provided.

#### Scenario: No standalone flag keeps ASDLC flow
- **WHEN** orchestrator runs without `--standalone`
- **THEN** it follows normal ASDLC-based project/feature artifact routing
- **AND** it does not treat local `overmind/` planning files as direct standalone inputs
