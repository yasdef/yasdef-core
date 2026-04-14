## ADDED Requirements

### Requirement: Selected feature artifacts are mirrored into worker runtime paths on branch `overmind`
Before orchestrator routes or starts worker phases for a run, it SHALL establish local branch `overmind` and mirror the selected ASDLC feature's `implementation_plan.md` into local `overmind/implementation_plan.md` and the selected feature's `requirements_ears.md` into local `overmind/reqirements_ears.md` on that branch.

#### Scenario: Successful feature sync populates local runtime copies
- **WHEN** orchestrator has selected one valid feature for the run
- **THEN** it SHALL perform the runtime mirror on local branch `overmind`
- **THEN** it SHALL copy that feature's `implementation_plan.md` to `overmind/implementation_plan.md`
- **AND** it SHALL copy that feature's `requirements_ears.md` to `overmind/reqirements_ears.md`
- **AND** subsequent worker phase scripts SHALL consume the local `overmind/` runtime copies for that run

#### Scenario: Selected feature EARS artifact is missing
- **WHEN** the selected feature does not contain a usable `requirements_ears.md`
- **THEN** orchestrator SHALL exit non-zero before `ai_design` starts
- **AND** it SHALL not leave a partially selected feature as a successful run context

### Requirement: Feature sync metadata is recorded separately from project binding
The worker repo SHALL persist current selected-feature state in `ai/feature_sync.yaml`, separate from `ai/project_overmind.yaml`, so routing decisions are traceable without mutating durable project binding.

#### Scenario: Sync metadata is written after feature selection
- **WHEN** orchestrator finishes selecting and mirroring a feature
- **THEN** it SHALL write `ai/feature_sync.yaml`
- **AND** the file SHALL include the selected `project_id`
- **AND** the file SHALL include the selected `feature_id`
- **AND** the file SHALL include the source paths for feature `implementation_plan.md` and `requirements_ears.md`
- **AND** the file SHALL include the local runtime mirror paths
- **AND** the file SHALL include local branch `overmind` as the runtime branch context
- **AND** the file SHALL include the selection mode for that run

#### Scenario: Durable project binding stays separate
- **WHEN** `ai/feature_sync.yaml` exists for the current run
- **THEN** `ai/project_overmind.yaml` SHALL remain the durable project binding artifact
- **AND** current feature state SHALL NOT be required to be stored in `ai/project_overmind.yaml`

### Requirement: Resume reuses valid selected-feature context
On `--resume <step>`, orchestrator SHALL reuse `ai/feature_sync.yaml` when it still points to a valid selected feature whose mirrored step context matches the requested resume step and the worker assignment remains valid.

#### Scenario: Resume metadata is still valid
- **WHEN** the operator runs `ai/scripts/orchestrator.sh --resume <step>` and `ai/feature_sync.yaml` points to a feature that still contains that assigned step for the bound worker UUID
- **THEN** orchestrator SHALL reuse that feature without prompting
- **AND** it SHALL refresh the local runtime mirrors from that same feature before phase evaluation continues

#### Scenario: Resume metadata is stale
- **WHEN** `ai/feature_sync.yaml` points to a feature that no longer exists, no longer contains the requested step, or no longer assigns that step to the bound worker UUID
- **THEN** orchestrator SHALL discard that stale feature selection
- **AND** it SHALL recompute candidate features using current source-of-truth data

### Requirement: Worker-owned plan updates sync back to the selected feature
When worker phases change local `overmind/implementation_plan.md` on branch `overmind`, orchestrator SHALL propagate the updated content back to the selected feature's source `implementation_plan.md` before considering the phase handoff successful.

#### Scenario: Local plan changes during planning or audit
- **WHEN** planning, ai_audit, or post_review modifies local `overmind/implementation_plan.md` for the selected feature
- **THEN** orchestrator SHALL copy the updated plan back to that selected feature's source `implementation_plan.md`
- **AND** the selected feature artifact SHALL remain the source of truth after sync-back

#### Scenario: Sync-back target is unavailable
- **WHEN** orchestrator cannot resolve or write the selected feature's source `implementation_plan.md` during sync-back
- **THEN** it SHALL exit non-zero with an explicit sync failure
- **AND** it SHALL not silently write the update to a different feature path
