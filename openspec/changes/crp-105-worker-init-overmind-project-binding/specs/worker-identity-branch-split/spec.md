## MODIFIED Requirements

### Requirement: Overmind registry updates are committed and pushed before leaving overmind
Worker init SHALL treat overmind-side worker registration as a prerequisite owned by the overmind source and SHALL NOT create, commit, or push overmind registry updates during local worker binding.

#### Scenario: Existing registration is consumed without shared mutation
- **WHEN** worker init finds a valid existing worker registration for the provided UUID in the provided overmind source
- **THEN** the script SHALL reuse that registration data for local binding
- **AND** SHALL NOT create any new overmind registry commit or push as part of worker init

#### Scenario: Missing registration blocks local binding
- **WHEN** the provided UUID is not already registered in the provided overmind source
- **THEN** worker init SHALL fail before any local binding artifact is written

### Requirement: Worker identity file is persisted on master branch
Worker init SHALL persist worker-local onboarding state as `ai/project_overmind.yaml` instead of `ai/<uuid>_dont_touch.txt`.

#### Scenario: Successful run writes project overmind binding artifact
- **WHEN** worker init completes successfully
- **THEN** the local worker repository SHALL contain `ai/project_overmind.yaml`
- **AND** it SHALL NOT require creation of `ai/<uuid>_dont_touch.txt`

#### Scenario: Re-run updates the same local binding artifact
- **WHEN** worker init is re-run with valid inputs
- **THEN** it SHALL update `ai/project_overmind.yaml` in place when content changes
- **AND** SHALL NOT create additional identity artifacts under `ai/`

### Requirement: Shared and local artifacts remain branch-scoped
Worker init SHALL keep shared worker registration data in the provided overmind source and SHALL keep local binding state in the worker repository under `ai/project_overmind.yaml`.

#### Scenario: Completion state verification
- **WHEN** worker init completes successfully
- **THEN** worker registration data SHALL remain in overmind-side project `workers.yaml` files
- **AND** worker-local binding state SHALL be durable in `ai/project_overmind.yaml`

### Requirement: Fail-fast orchestrator detection remains unchanged
Worker init SHALL fail fast when the provided overmind source path cannot be used to resolve exactly one registered worker UUID for local binding.

#### Scenario: Overmind source path is unusable
- **WHEN** the provided overmind source path is missing or does not expose usable project `workers.yaml` files
- **THEN** the script SHALL exit non-zero with a meaningful validation error
