## MODIFIED Requirements

### Requirement: Next-step discovery runs from synced coordinator branch
The orchestrator SHALL resolve next-step discovery from the ASDLC project bound in `ai/project_overmind.yaml`, switch to local branch `overmind`, scan feature folders under that project, and sync the selected feature's coordinator artifacts into local `overmind/` runtime paths on branch `overmind` before phase execution continues.

#### Scenario: Bound ASDLC project path is missing
- **WHEN** orchestrator starts next-step discovery and `ai/project_overmind.yaml` is missing, missing `project_id`, or resolves to a project path that does not exist under the configured ASDLC source
- **THEN** orchestrator exits non-zero with an explicit fail-fast error
- **AND** it does not continue discovery

#### Scenario: Selected feature is mirrored before execution
- **WHEN** orchestrator resolves a valid selected feature under the bound project
- **THEN** it performs the runtime mirror on local branch `overmind`
- **AND** it mirrors that feature's `implementation_plan.md` into local `overmind/implementation_plan.md`
- **AND** it mirrors that feature's `requirements_ears.md` into local `overmind/reqirements_ears.md`
- **AND** it uses those local runtime copies for subsequent routing and phase execution

### Requirement: Worker UUID is resolved from dont-touch identity filename
The orchestrator SHALL resolve worker identity from `ai/project_overmind.yaml` by reading the bound `worker_uuid` instead of reading `ai/*_dont_touch.txt`.

#### Scenario: Binding file present and valid
- **WHEN** `ai/project_overmind.yaml` exists and contains a non-empty `worker_uuid`
- **THEN** orchestrator uses that value as the worker UUID for feature and step assignment filtering

#### Scenario: Binding file missing
- **WHEN** `ai/project_overmind.yaml` is absent
- **THEN** orchestrator exits non-zero with an explicit fail-fast error

#### Scenario: Binding file missing worker identity
- **WHEN** `ai/project_overmind.yaml` exists but does not contain a usable `worker_uuid`
- **THEN** orchestrator exits non-zero with an explicit fail-fast error and does not select a step

### Requirement: Next work item is filtered by assigned worker UUID
The orchestrator SHALL scan `implementation_plan.md` for each feature under the bound project, consider only step blocks whose assignment header is `#### Assigned: <uuid>` matching the bound worker UUID, and build a feature candidate set from those matches.

#### Scenario: Single candidate feature is auto-selected
- **WHEN** exactly one feature under the bound project contains worker-assigned unchecked work for the bound worker UUID
- **THEN** orchestrator auto-selects that feature
- **AND** it selects the first unchecked bullet from the first assigned matching step block in that feature

#### Scenario: Requested step constrains the candidate set
- **WHEN** the operator supplies `--step <step>` or `--resume <step>`
- **THEN** orchestrator limits candidate features to those whose `implementation_plan.md` contains that step assigned to the bound worker UUID

#### Scenario: Unassigned or differently assigned work is ignored
- **WHEN** unchecked bullets exist only in step blocks not assigned to the bound worker UUID
- **THEN** orchestrator ignores those bullets during candidate-feature and next-step selection

### Requirement: Missing worker assignments fail fast
The orchestrator SHALL fail fast when no feature under the bound project contains any step block assigned to the bound worker UUID.

#### Scenario: No assigned steps for worker in the bound project
- **WHEN** orchestrator scans all feature `implementation_plan.md` files under the bound project and finds no `#### Assigned: <uuid>` block matching the bound worker UUID
- **THEN** orchestrator exits non-zero with an explicit fail-fast error and does not start design or implementation

#### Scenario: Assigned steps complete with no free bullets
- **WHEN** assigned step blocks exist for the bound worker UUID across the bound project's features but all assigned checklist bullets are complete
- **THEN** orchestrator reports no available work for this worker and exits without starting a new step

## ADDED Requirements

### Requirement: Multi-feature ambiguity requires explicit user choice
The orchestrator SHALL prompt the user to select the active feature when more than one candidate feature remains after worker-assignment and requested-step filtering.

#### Scenario: Multiple candidate features exist
- **WHEN** two or more candidate features remain eligible for the current run
- **THEN** orchestrator SHALL ask the user which feature to run
- **AND** it SHALL NOT silently pick one based on discovery order, lexical order, or file modification time

#### Scenario: Resume metadata removes ambiguity
- **WHEN** `--resume <step>` is requested and valid local feature-sync metadata already points to one candidate feature for that same step
- **THEN** orchestrator SHALL reuse that feature without prompting
