## ADDED Requirements

### Requirement: feature_meta_sync.yaml contains exactly four fields
The orchestrator SHALL persist selected-feature state to `.asdlc_worker/feature_meta_sync.yaml` containing exactly the fields `project_id`, `worker_uuid`, `feature_id`, and `selected_step`. The file MUST NOT contain `source_implementation_plan_path`, `source_requirements_ears_path`, `runtime_implementation_plan_path`, `runtime_requirements_ears_path`, `source_feature_path`, `bound_project_path`, `overmind_source_path`, `selection_mode`, `runtime_branch`, or `requested_step`.

#### Scenario: Fresh feature selection writes the four fields
- **WHEN** the orchestrator completes feature selection in default mode and writes `feature_meta_sync.yaml`
- **THEN** the file contains exactly `project_id`, `worker_uuid`, `feature_id`, and `selected_step`
- **THEN** no other top-level key is present in the file

#### Scenario: Resume reuse rewrites the four fields
- **WHEN** the orchestrator resumes with an existing `feature_meta_sync.yaml` and reuse validation succeeds
- **THEN** the rewritten file contains exactly `project_id`, `worker_uuid`, `feature_id`, and `selected_step`

### Requirement: feature_meta_sync.yaml is the only persisted feature-sync state file
The orchestrator SHALL NOT read, write, validate, or rely on `.asdlc_worker/feature_sync.yaml` for any feature-selection or resume decision. The old filename is treated as if it does not exist.

#### Scenario: Old feature_sync.yaml is ignored on resume
- **WHEN** `.asdlc_worker/feature_sync.yaml` is present from a prior installation and `.asdlc_worker/feature_meta_sync.yaml` is absent
- **THEN** the orchestrator treats the situation as "no metadata file present"
- **THEN** resume falls through to feature discovery

#### Scenario: Old feature_sync.yaml is not deleted automatically
- **WHEN** the orchestrator runs successfully in default mode with `.asdlc_worker/feature_sync.yaml` present from a prior installation
- **THEN** the orchestrator does not delete or rewrite `.asdlc_worker/feature_sync.yaml`

### Requirement: Resume reuse validates identity and rederives paths
Resume reuse of `feature_meta_sync.yaml` SHALL validate `project_id` and `worker_uuid` against the binding file and rederive plan/ears paths as `<BOUND_PROJECT_PATH>/<feature_id>/implementation_plan.md` and `.../requirements_ears.md`. Reuse MUST succeed only when those derived paths exist and the requirements_ears file is non-empty.

#### Scenario: Reuse succeeds when identity matches and derived paths exist
- **WHEN** `feature_meta_sync.yaml` exists with `project_id` and `worker_uuid` matching the binding file, and the derived plan and ears files exist and are non-empty
- **THEN** reuse succeeds and the orchestrator skips discovery

#### Scenario: Reuse fails when project_id mismatches
- **WHEN** `feature_meta_sync.yaml` exists but its `project_id` differs from the binding file
- **THEN** reuse fails and the orchestrator falls through to slow-path discovery

#### Scenario: Reuse fails when worker_uuid mismatches
- **WHEN** `feature_meta_sync.yaml` exists but its `worker_uuid` differs from the binding file
- **THEN** reuse fails and the orchestrator falls through to slow-path discovery

#### Scenario: Reuse fails when derived feature directory is missing
- **WHEN** `feature_meta_sync.yaml` exists but `<BOUND_PROJECT_PATH>/<feature_id>/implementation_plan.md` does not exist
- **THEN** reuse fails and the orchestrator falls through to slow-path discovery

#### Scenario: Reuse fails when requested step is no longer assigned to this worker
- **WHEN** `feature_meta_sync.yaml` exists and `--resume <step>` is passed, but the derived plan no longer has `<step>` assigned to this worker
- **THEN** reuse fails and the orchestrator falls through to slow-path discovery
