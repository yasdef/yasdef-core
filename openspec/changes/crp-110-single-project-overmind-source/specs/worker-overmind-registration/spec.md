## MODIFIED Requirements

### Requirement: Worker init fails fast when orchestrator branch is unavailable
The worker init flow SHALL ask for the path to a single ASDLC project repo, SHALL verify the path exists, SHALL verify that `<project_repo>/workers.yaml` exists at the repo root, and SHALL verify that `<project_repo>/init_progress_definition.yaml` exists with a non-empty `meta_info.project_id`. It SHALL fail fast with a meaningful message when any of these checks fails.

#### Scenario: Provided overmind project repo path does not exist
- **WHEN** the operator provides an `overmind_source_path` that does not exist
- **THEN** the script SHALL exit non-zero
- **AND** SHALL print an error explaining that the overmind project repo path was not found

#### Scenario: Project repo is missing root workers.yaml
- **WHEN** the operator provides an existing path but `<project_repo>/workers.yaml` is missing
- **THEN** the script SHALL exit non-zero
- **AND** SHALL print an error explaining that the project repo does not contain a root `workers.yaml`

#### Scenario: Project repo is missing init_progress_definition.yaml
- **WHEN** the operator provides an existing path but `<project_repo>/init_progress_definition.yaml` is missing
- **THEN** the script SHALL exit non-zero
- **AND** SHALL print an error explaining that the project repo does not contain `init_progress_definition.yaml`

#### Scenario: init_progress_definition.yaml is missing meta_info.project_id
- **WHEN** `<project_repo>/init_progress_definition.yaml` exists but does not contain a non-empty `meta_info.project_id`
- **THEN** the script SHALL exit non-zero
- **AND** SHALL print an error explaining that `meta_info.project_id` is required for project identity

### Requirement: Worker is registered idempotently in coordinator registry
Worker init SHALL validate that the operator-provided worker UUID is registered exactly once in `<project_repo>/workers.yaml`, SHALL read project identity from `<project_repo>/init_progress_definition.yaml` `meta_info.project_id`, and SHALL NOT modify any shared overmind registry files during this flow.

#### Scenario: Provided uuid matches one entry in root workers.yaml
- **WHEN** `<project_repo>/workers.yaml` contains exactly one entry whose `uuid` matches the operator-provided worker UUID
- **THEN** the script SHALL use that matched entry as the source of worker metadata for local binding
- **AND** SHALL set `project_id` in `ai/project_overmind.yaml` from `<project_repo>/init_progress_definition.yaml` `meta_info.project_id`
- **AND** SHALL set `overmind_source_path` in `ai/project_overmind.yaml` to the resolved single-project repo path
- **AND** SHALL NOT append, edit, commit, or push any overmind worker registry content

#### Scenario: Provided uuid is not registered
- **WHEN** `<project_repo>/workers.yaml` contains no worker entry whose `uuid` matches the operator-provided worker UUID
- **THEN** the script SHALL exit non-zero
- **AND** SHALL print an error explaining that the worker UUID is not registered in the provided project repo

#### Scenario: Provided uuid resolves ambiguously inside the single workers.yaml
- **WHEN** `<project_repo>/workers.yaml` contains more than one entry whose `uuid` matches the operator-provided worker UUID
- **THEN** the script SHALL exit non-zero
- **AND** SHALL print an error explaining that the worker UUID resolved to multiple entries in the registry

#### Scenario: Multi-project source layout is rejected
- **WHEN** the operator provides a path that contains nested `projects/<id>/workers.yaml` files but no root `workers.yaml`
- **THEN** the script SHALL exit non-zero with the missing-root-`workers.yaml` error
- **AND** SHALL NOT attempt recursive discovery across nested project directories
