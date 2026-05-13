## MODIFIED Requirements

### Requirement: Next-step discovery runs from synced coordinator branch
The orchestrator SHALL resolve next-step discovery against the single ASDLC project repo bound in `ai/project_overmind.yaml` by treating `overmind_source_path` as the project repo path directly (no `projects/<id>/` or `<id>/` fallback). It SHALL switch to local branch `overmind`, scan feature folders directly under the bound project repo path, and sync the selected feature's coordinator artifacts into local `overmind/` runtime paths on branch `overmind` before phase execution continues.

#### Scenario: Bound project repo path is missing
- **WHEN** orchestrator starts next-step discovery and `ai/project_overmind.yaml` is missing, missing `project_id`, missing `overmind_source_path`, or `overmind_source_path` does not exist on disk
- **THEN** orchestrator exits non-zero with an explicit fail-fast error
- **AND** it does not continue discovery

#### Scenario: Bound project_id does not match init_progress_definition.yaml
- **WHEN** `<overmind_source_path>/init_progress_definition.yaml` is missing, or its `meta_info.project_id` does not match the bound `project_id` in `ai/project_overmind.yaml`
- **THEN** orchestrator exits non-zero with an explicit project-identity-mismatch error and instructs the operator to re-run `ai/scripts/init_worker.sh`
- **AND** it does not continue discovery

#### Scenario: Selected feature is mirrored before execution
- **WHEN** orchestrator resolves a valid selected feature directly under the bound project repo path
- **THEN** it performs the runtime mirror on local branch `overmind`
- **AND** it mirrors that feature's `implementation_plan.md` into local `overmind/implementation_plan.md`
- **AND** it mirrors that feature's `requirements_ears.md` into local `overmind/reqirements_ears.md`
- **AND** it uses those local runtime copies for subsequent routing and phase execution

### Requirement: Next work item is filtered by assigned worker UUID
The orchestrator SHALL enumerate feature subdirectories directly under the bound project repo path, SHALL skip `.git` and any subdirectory that does not contain `implementation_plan.md`, SHALL consider only step blocks whose assignment header is `#### Assigned: <uuid>` matching the bound worker UUID, and SHALL build a feature candidate set from those matches.

#### Scenario: Single candidate feature is auto-selected
- **WHEN** exactly one feature subdirectory under the bound project repo path contains worker-assigned unchecked work for the bound worker UUID
- **THEN** orchestrator auto-selects that feature
- **AND** it selects the first unchecked bullet from the first assigned matching step block in that feature

#### Scenario: Requested step constrains the candidate set
- **WHEN** the operator supplies `--step <step>` or `--resume <step>`
- **THEN** orchestrator limits candidate features to those whose `implementation_plan.md` directly under the bound project repo path contains that step assigned to the bound worker UUID

#### Scenario: Non-feature subdirectories are skipped
- **WHEN** orchestrator enumerates subdirectories of the bound project repo path
- **THEN** it skips `.git`
- **AND** it skips any subdirectory that does not contain `implementation_plan.md`
- **AND** those skipped subdirectories never appear in the candidate set

#### Scenario: Unassigned or differently assigned work is ignored
- **WHEN** unchecked bullets exist only in step blocks not assigned to the bound worker UUID
- **THEN** orchestrator ignores those bullets during candidate-feature and next-step selection

### Requirement: Missing worker assignments fail fast
The orchestrator SHALL fail fast when no feature subdirectory directly under the bound project repo path contains any step block assigned to the bound worker UUID.

#### Scenario: No assigned steps for worker in the bound project repo
- **WHEN** orchestrator scans all feature `implementation_plan.md` files directly under the bound project repo path and finds no `#### Assigned: <uuid>` block matching the bound worker UUID
- **THEN** orchestrator exits non-zero with an explicit fail-fast error and does not start design or implementation

#### Scenario: Assigned steps complete with no free bullets
- **WHEN** assigned step blocks exist for the bound worker UUID across the bound project repo's features but all assigned checklist bullets are complete
- **THEN** orchestrator reports no available work for this worker and exits without starting a new step
