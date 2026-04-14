## ADDED Requirements

### Requirement: Worker binding persists ASDLC project identity
Worker init SHALL persist `ai/project_overmind.yaml` as the durable local project binding artifact and SHALL include the ASDLC source path, bound `project_id`, worker UUID, and matched worker metadata.

#### Scenario: Successful binding stores project-scoped worker identity
- **WHEN** the operator provides a valid worker UUID and an ASDLC source path that contains exactly one matching registered worker entry in exactly one project
- **THEN** `ai/project_overmind.yaml` SHALL be created or updated
- **AND** the file SHALL contain the ASDLC source path used for validation
- **AND** the file SHALL contain the resolved `project_id`
- **AND** the file SHALL contain the validated worker UUID
- **AND** the file SHALL contain the matched worker `class`
- **AND** the file SHALL contain the matched worker `status`

#### Scenario: Project binding is ambiguous
- **WHEN** the provided ASDLC source contains matching worker registrations in more than one project
- **THEN** worker init SHALL exit non-zero
- **AND** it SHALL not create an ambiguous `ai/project_overmind.yaml`

### Requirement: Project binding content is deterministic on re-run
Worker init SHALL rewrite `ai/project_overmind.yaml` deterministically when the operator re-runs the flow with the same resolved project and unchanged worker metadata.

#### Scenario: Re-running with the same project and metadata is byte-identical
- **WHEN** the operator runs worker init multiple times with the same ASDLC source path, the same resolved `project_id`, the same worker UUID, and unchanged matched worker metadata
- **THEN** the resulting `ai/project_overmind.yaml` content SHALL be byte-identical across runs

#### Scenario: Re-running with changed project metadata refreshes the binding
- **WHEN** the operator re-runs worker init and the resolved `project_id`, worker `class`, or worker `status` differs from the current file content
- **THEN** `ai/project_overmind.yaml` SHALL be updated to reflect the latest resolved binding

### Requirement: Current feature selection is not stored in the durable binding
Worker init and orchestrator SHALL keep active feature selection outside `ai/project_overmind.yaml` so durable project binding is independent from per-run feature sync state.

#### Scenario: Feature sync metadata exists after orchestrator selection
- **WHEN** orchestrator has already written current feature-sync metadata for a run
- **THEN** `ai/project_overmind.yaml` SHALL still represent only project binding state
- **AND** current `feature_id` or step-selection context SHALL NOT be required to live in that file
