## ADDED Requirements

### Requirement: Routing writes minimal feature_meta_sync.yaml without mirroring
After feature selection in default mode, the orchestrator SHALL write `.asdlc_worker/feature_meta_sync.yaml` containing exactly `project_id`, `worker_uuid`, `feature_id`, and `selected_step`. The orchestrator MUST NOT mirror `implementation_plan.md` or `requirements_ears.md` from the bound-source feature directory into `.asdlc_worker/overmind/`.

#### Scenario: Single-candidate routing writes meta sync and skips mirroring
- **WHEN** the orchestrator selects a single candidate feature for the worker in default mode
- **THEN** `.asdlc_worker/feature_meta_sync.yaml` is written with the four required fields
- **THEN** no copy of `implementation_plan.md` or `requirements_ears.md` is created under `.asdlc_worker/overmind/`

#### Scenario: User-prompted routing writes meta sync and skips mirroring
- **WHEN** multiple candidate features are present and the operator selects one interactively
- **THEN** `.asdlc_worker/feature_meta_sync.yaml` is written with the four required fields
- **THEN** no copy of `implementation_plan.md` or `requirements_ears.md` is created under `.asdlc_worker/overmind/`

### Requirement: Routing operates on bound source paths
After feature selection in default mode, all subsequent reads of `implementation_plan.md` and `requirements_ears.md` for the selected feature SHALL be performed against `<BOUND_PROJECT_PATH>/<feature_id>/implementation_plan.md` and `<BOUND_PROJECT_PATH>/<feature_id>/requirements_ears.md`.

#### Scenario: Step analysis reads the bound source plan
- **WHEN** the orchestrator analyzes the selected feature's plan to determine assigned and unchecked steps
- **THEN** the analysis reads from `<BOUND_PROJECT_PATH>/<feature_id>/implementation_plan.md`

#### Scenario: Phase scripts receive bound source paths in env vars
- **WHEN** the orchestrator invokes any phase script in default mode after routing
- **THEN** `$ASDLC_RUNTIME_PLAN_PATH` and `$ASDLC_RUNTIME_EARS_PATH` resolve to bound-source paths for the selected feature
