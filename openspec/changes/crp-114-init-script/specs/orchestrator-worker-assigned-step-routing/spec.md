## REMOVED Requirements

### Requirement: Worker UUID is resolved from dont-touch identity filename
**Reason**: The root `ai/*_dont_touch.txt` identity file is not supported in the `.asdlc_worker/` runtime layout.
**Migration**: Resolve worker identity from the durable binding metadata stored under `.asdlc_worker/`.

## MODIFIED Requirements

### Requirement: Next-step discovery runs from synced coordinator branch
The orchestrator SHALL run from `<worker-repo>/.asdlc_worker/scripts`, resolve `<worker-repo>` as the parent of `.asdlc_worker`, switch that worker repository to local Git branch `overmind`, and sync it from remote Git branch `overmind` before reading runtime or source artifacts for next-step discovery.

#### Scenario: Local overmind branch missing
- **WHEN** orchestrator starts next-step discovery from `.asdlc_worker` and local Git branch `overmind` does not exist in the worker repo root
- **THEN** orchestrator exits non-zero with an explicit fail-fast error and does not continue discovery

#### Scenario: Remote overmind branch missing
- **WHEN** orchestrator attempts to sync local `overmind` and remote Git branch `overmind` is missing
- **THEN** orchestrator exits non-zero with an explicit fail-fast error and does not parse `implementation_plan.md`

#### Scenario: Remote sync failure
- **WHEN** orchestrator cannot complete sync of local `overmind` from remote `overmind`
- **THEN** orchestrator exits non-zero with an explicit fail-fast error and does not start design or implementation

### Requirement: Next work item is filtered by assigned worker UUID
The orchestrator SHALL select the next work item only from step blocks whose assignment header is `#### Assigned: <uuid>` matching the worker UUID resolved from `.asdlc_worker/` binding metadata.

#### Scenario: Assigned step has free bullet
- **WHEN** at least one step block assigned to local UUID contains unchecked bullets
- **THEN** orchestrator selects the first unchecked bullet from the first assigned matching step block

#### Scenario: Unassigned or differently assigned step contains free bullet
- **WHEN** unchecked bullets exist in step blocks not assigned to local UUID
- **THEN** orchestrator ignores those bullets during next-step selection

### Requirement: Missing worker assignments fail fast
The orchestrator SHALL fail fast when no step blocks in the selected `implementation_plan.md` are assigned to the worker UUID resolved from `.asdlc_worker/` binding metadata.

#### Scenario: No assigned steps for worker
- **WHEN** orchestrator parses `implementation_plan.md` and finds no `#### Assigned: <uuid>` block matching local worker UUID
- **THEN** orchestrator exits non-zero with an explicit fail-fast error and does not start design or implementation

#### Scenario: Assigned steps complete with no free bullets
- **WHEN** assigned step blocks exist for local worker UUID but all bullets are complete
- **THEN** orchestrator reports no available work for this worker and exits without starting a new step

## ADDED Requirements

### Requirement: Orchestrator resolves runtime and repo roots from .asdlc_worker
The orchestrator SHALL derive runtime paths from `.asdlc_worker` and project-code paths from the parent worker repo root.

#### Scenario: Orchestrator prepares phase paths
- **WHEN** orchestrator starts from `<worker-repo>/.asdlc_worker/scripts/orchestrator.sh`
- **THEN** it SHALL read process docs, setup, prompts, logs, and worker-local state from `<worker-repo>/.asdlc_worker`
- **AND** it SHALL execute git operations and apply source changes in `<worker-repo>`

#### Scenario: Orchestrator starts from unsupported layout
- **WHEN** orchestrator starts from a script path not under `<worker-repo>/.asdlc_worker/scripts`
- **THEN** it SHALL exit non-zero with a meaningful unsupported-layout message
