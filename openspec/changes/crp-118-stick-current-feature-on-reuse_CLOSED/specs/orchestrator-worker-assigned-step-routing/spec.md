## MODIFIED Requirements

### Requirement: Next-step discovery runs from synced coordinator branch
The orchestrator SHALL switch to local Git branch `overmind` and sync it from remote Git branch `overmind` before reading `implementation_plan.md` for next-step discovery.

#### Scenario: Local overmind branch missing
- **WHEN** orchestrator starts next-step discovery and local Git branch `overmind` does not exist
- **THEN** orchestrator exits non-zero with an explicit fail-fast error and does not continue discovery

#### Scenario: Remote overmind branch missing
- **WHEN** orchestrator attempts to sync local `overmind` and remote Git branch `overmind` is missing
- **THEN** orchestrator exits non-zero with an explicit fail-fast error and does not parse `implementation_plan.md`

#### Scenario: Remote sync failure
- **WHEN** orchestrator cannot complete sync of local `overmind` from remote `overmind`
- **THEN** orchestrator exits non-zero with an explicit fail-fast error and does not start design or implementation

### Requirement: Worker UUID is resolved from dont-touch identity filename
The orchestrator SHALL resolve worker identity from exactly one file matching `ai/*_dont_touch.txt` by using the filename prefix before `_dont_touch.txt` as the worker UUID.

#### Scenario: Identity file present and valid
- **WHEN** exactly one file matches `ai/*_dont_touch.txt` and the filename prefix is a non-empty UUID value
- **THEN** orchestrator uses that prefix as worker UUID for step assignment filtering

#### Scenario: Identity file missing
- **WHEN** no file matches `ai/*_dont_touch.txt`
- **THEN** orchestrator exits non-zero with an explicit fail-fast error

#### Scenario: Identity file ambiguous
- **WHEN** multiple files match `ai/*_dont_touch.txt`
- **THEN** orchestrator exits non-zero with an explicit fail-fast error and does not select a step

### Requirement: Next work item is filtered by assigned worker UUID
The orchestrator SHALL select the next work item only from step blocks whose assignment header is `#### Assigned: <uuid>` matching the resolved worker UUID.

#### Scenario: Assigned step has free bullet
- **WHEN** at least one step block assigned to local UUID contains unchecked bullets
- **THEN** orchestrator selects the first unchecked bullet from the first assigned matching step block

#### Scenario: Unassigned or differently assigned step contains free bullet
- **WHEN** unchecked bullets exist in step blocks not assigned to local UUID
- **THEN** orchestrator ignores those bullets during next-step selection

### Requirement: Missing worker assignments fail fast
The orchestrator SHALL fail fast when no step blocks in `implementation_plan.md` are assigned to the resolved worker UUID.

#### Scenario: No assigned steps for worker
- **WHEN** orchestrator parses `implementation_plan.md` and finds no `#### Assigned: <uuid>` block matching local worker UUID
- **THEN** orchestrator exits non-zero with an explicit fail-fast error and does not start design or implementation

#### Scenario: Assigned steps complete with no free bullets
- **WHEN** assigned step blocks exist for local worker UUID but all bullets are complete
- **THEN** orchestrator reports no available work for this worker and exits without starting a new step

### Requirement: Ordinary startup does not silently switch away from a valid current feature
During startup and re-run flows (non-resume), if `feature_sync.yaml` is present and passes reuse validation, the orchestrator SHALL NOT switch to a different feature via global discovery. If the valid current feature is blocked or exhausted, the orchestrator SHALL fail fast with an explicit error.

#### Scenario: Ordinary startup reuses valid current feature
- **WHEN** the orchestrator starts in non-standalone mode without `--resume` and `feature_sync.yaml` passes reuse validation and the stored feature has a runnable step
- **THEN** the orchestrator uses the stored feature without running global candidate discovery

#### Scenario: Ordinary startup fails fast on blocked current feature
- **WHEN** the orchestrator starts and `feature_sync.yaml` passes reuse validation but the stored feature is blocked by an upstream step
- **THEN** the orchestrator exits non-zero with an error naming the current feature and the blocking step
- **THEN** the orchestrator does not scan other features under the bound project

#### Scenario: Ordinary startup fails fast on exhausted current feature
- **WHEN** the orchestrator starts and `feature_sync.yaml` passes reuse validation but all assigned steps in the stored feature are complete
- **THEN** the orchestrator exits non-zero with an error naming the current feature as exhausted
- **THEN** the orchestrator does not scan other features under the bound project
