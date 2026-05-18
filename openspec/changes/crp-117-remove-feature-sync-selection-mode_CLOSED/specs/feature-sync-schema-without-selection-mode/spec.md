## ADDED Requirements

### Requirement: feature_sync.yaml omits selection_mode field
The orchestrator runtime SHALL write `feature_sync.yaml` without a `selection_mode` field. The file MUST contain only: `project_id`, `feature_id`, `worker_uuid`, `overmind_source_path`, `bound_project_path`, `source_feature_path`, `source_implementation_plan_path`, `source_requirements_ears_path`, `runtime_implementation_plan_path`, `runtime_requirements_ears_path`, `runtime_branch`, `requested_step`, and `selected_step`.

#### Scenario: Fresh feature selection writes no selection_mode
- **WHEN** the orchestrator completes feature selection and writes `feature_sync.yaml`
- **THEN** the file does not contain a `selection_mode` key

#### Scenario: Resume reuse writes no selection_mode
- **WHEN** the orchestrator resumes with an existing `feature_sync.yaml` and reuse validation succeeds
- **THEN** the updated `feature_sync.yaml` does not contain a `selection_mode` key

#### Scenario: Existing file with selection_mode is silently ignored on reuse
- **WHEN** the orchestrator reads an existing `feature_sync.yaml` that contains a `selection_mode` field
- **THEN** the orchestrator ignores the `selection_mode` field during reuse validation
- **THEN** reuse succeeds or fails based solely on `project_id`, `worker_uuid`, `runtime_branch`, `feature_id`, `source_implementation_plan_path`, and `source_requirements_ears_path`
