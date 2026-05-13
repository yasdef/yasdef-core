## ADDED Requirements

### Requirement: Worker binding persists runtime root identity
`init_asdlc_worker.sh` SHALL persist `.asdlc_worker/asdlc_worker.yaml` as the durable local runtime-root artifact and SHALL include the resolved worker repository root.

#### Scenario: Runtime root binding is stored
- **WHEN** the init flow installs `.asdlc_worker` into a target repo
- **THEN** `.asdlc_worker/asdlc_worker.yaml` SHALL be created or updated
- **AND** it SHALL contain the resolved target repo root path

### Requirement: Worker project binding persists under .asdlc_worker
`register_worker.sh` SHALL persist ASDLC project binding metadata under `.asdlc_worker/` and SHALL include the ASDLC source path, bound `project_id`, worker UUID, and matched worker metadata.

#### Scenario: Successful binding stores project-scoped worker identity
- **WHEN** the operator provides a valid worker UUID and an ASDLC project repo path that contains exactly one matching registered worker entry
- **THEN** the runtime binding file under `.asdlc_worker/` SHALL be created or updated
- **AND** it SHALL contain the ASDLC project repo path used for validation
- **AND** it SHALL contain the resolved `project_id`
- **AND** it SHALL contain the validated worker UUID
- **AND** it SHALL contain the matched worker `class`
- **AND** it SHALL contain the matched worker `status`

### Requirement: Project binding content is deterministic on re-run
`register_worker.sh` SHALL rewrite `.asdlc_worker/` project binding metadata deterministically when the operator re-runs the flow with the same resolved project and unchanged worker metadata.

#### Scenario: Re-running with the same project and metadata is byte-identical
- **WHEN** the operator runs `register_worker.sh` multiple times with the same ASDLC project repo path, the same resolved `project_id`, the same worker UUID, and unchanged matched worker metadata
- **THEN** the resulting `.asdlc_worker/` binding metadata content SHALL be byte-identical across runs

#### Scenario: Re-running with changed project metadata refreshes the binding
- **WHEN** the operator re-runs `register_worker.sh` and the resolved `project_id`, worker `class`, or worker `status` differs from the current binding metadata
- **THEN** `.asdlc_worker/` binding metadata SHALL be updated to reflect the latest resolved binding

### Requirement: Current feature selection is not stored in durable project binding
`register_worker.sh` and orchestrator SHALL keep active feature selection outside the durable project binding metadata so durable project binding is independent from per-run feature sync state.

#### Scenario: Feature sync metadata exists after orchestrator selection
- **WHEN** orchestrator has already written current feature-sync metadata for a run
- **THEN** durable project binding metadata SHALL still represent only project binding state
- **AND** current `feature_id` or step-selection context SHALL NOT be required to live in the durable project binding file
