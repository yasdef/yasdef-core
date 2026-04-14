## ADDED Requirements

### Requirement: Worker init creates a local overmind binding artifact
Worker init SHALL create `ai/project_overmind.yaml` in the local worker repository after validating a provided worker UUID against an existing overmind-side registration.

#### Scenario: Successful binding creates local project overmind file
- **WHEN** the operator provides a valid worker UUID and an overmind repo path that contains exactly one matching registered worker entry
- **THEN** `ai/project_overmind.yaml` SHALL be created in the local worker repository
- **AND** the file SHALL contain the overmind source path used for validation
- **AND** the file SHALL contain the validated worker UUID
- **AND** the file SHALL contain the matched worker `class`
- **AND** the file SHALL contain the matched worker `status`

### Requirement: Local overmind binding content is deterministic on re-run
Worker init SHALL keep `ai/project_overmind.yaml` as the canonical local binding artifact and SHALL rewrite it deterministically when the operator re-runs the flow with valid inputs.

#### Scenario: Re-running with the same inputs is byte-identical
- **WHEN** the operator runs worker init multiple times with the same valid worker UUID, the same overmind repo path, and unchanged matched worker metadata
- **THEN** the resulting `ai/project_overmind.yaml` content SHALL be byte-identical across runs

#### Scenario: Re-running with changed worker metadata refreshes the local binding
- **WHEN** the operator re-runs worker init for the same UUID after the matched overmind worker entry has a different `class` or `status`
- **THEN** `ai/project_overmind.yaml` SHALL be updated to reflect the current matched worker metadata

### Requirement: Legacy worker identity artifact is not recreated
Worker init SHALL use `ai/project_overmind.yaml` as the local onboarding artifact and SHALL NOT create or require `ai/<uuid>_dont_touch.txt`.

#### Scenario: Successful binding leaves no legacy identity file
- **WHEN** worker init completes successfully under the new binding flow
- **THEN** the script SHALL NOT create any file matching `ai/*_dont_touch.txt`
