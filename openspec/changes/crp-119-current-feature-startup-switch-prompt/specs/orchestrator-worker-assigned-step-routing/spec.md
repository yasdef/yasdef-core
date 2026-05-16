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

### Requirement: Interactive feature selection includes explicit current-feature handoff path
When the operator chooses `Change feature` at the startup prompt and global discovery surfaces multiple candidates, the feature picker SHALL place the candidate matching the prior current feature at position 1 (first) in the list with a `(CURRENT)` label. The operator SHALL then select from the full candidate list, including the relabeled current feature.

#### Scenario: Feature picker places current feature first with label
- **WHEN** global discovery finds multiple candidate features and one of them matches the feature ID the operator chose to switch away from
- **THEN** that feature is listed first in the picker and its display name includes `(CURRENT)`
- **THEN** all other candidates follow in their normal discovery order

#### Scenario: Feature picker shows normally when prior current feature is not a candidate
- **WHEN** global discovery produces a candidate list that does not include the prior current feature ID
- **THEN** the feature picker displays candidates in normal discovery order without any `(CURRENT)` label

#### Scenario: Auto-selection when only one candidate exists after change
- **WHEN** the operator chooses Change feature and global discovery finds exactly one candidate
- **THEN** the orchestrator auto-selects that single candidate without prompting
