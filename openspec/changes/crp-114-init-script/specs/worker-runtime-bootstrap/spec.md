## ADDED Requirements

### Requirement: Init prompts for target repository path
The worker runtime init flow SHALL ask the operator for the target repository path before validating or mutating any target files.

#### Scenario: Operator provides target path
- **WHEN** the init script starts without a preselected target repository
- **THEN** it SHALL prompt the operator to enter a target repository path
- **AND** it SHALL use that path as the only target for validation and installation

### Requirement: Target repository path is validated before mutation
The worker runtime init flow SHALL validate the target path before copying runtime files or writing worker metadata.

#### Scenario: Target path does not exist
- **WHEN** the operator provides a path that does not exist
- **THEN** init SHALL exit non-zero with a meaningful message that includes the missing path
- **AND** it SHALL NOT create `.asdlc_worker`

#### Scenario: Target path is not a directory
- **WHEN** the operator provides a path that exists but is not a directory
- **THEN** init SHALL exit non-zero with a meaningful message that the target is not a directory
- **AND** it SHALL NOT create `.asdlc_worker`

#### Scenario: Target path is nested inside another git repository
- **WHEN** the operator provides a path inside a git repository but the path is not that repository root
- **THEN** init SHALL exit non-zero with a meaningful message that the target must be the git repository root
- **AND** it SHALL NOT create `.asdlc_worker`

### Requirement: Init creates git repository when absent
The worker runtime init flow SHALL initialize git in a valid target directory when that directory is not already inside a git repository.

#### Scenario: Target has no git repository
- **WHEN** the operator provides an existing directory that is not inside any git repository
- **THEN** init SHALL run `git init` in that target directory
- **AND** it SHALL continue installation using that directory as the worker repo root

#### Scenario: Target is git repository root
- **WHEN** the operator provides a path that resolves to the root of an existing git repository
- **THEN** init SHALL use that path as the worker repo root
- **AND** it SHALL NOT reinitialize git

### Requirement: Worker runtime is installed under .asdlc_worker
The worker runtime init flow SHALL install YASDEF worker runtime files under `<target-repo>/.asdlc_worker/`.

#### Scenario: First-time installation
- **WHEN** the target repo does not contain `.asdlc_worker`
- **THEN** init SHALL create `<target-repo>/.asdlc_worker`
- **AND** it SHALL copy the YASDEF `ai/` runtime content into `.asdlc_worker`
- **AND** it SHALL create `.asdlc_worker/asdlc_worker.yaml` containing the resolved worker repo root

### Requirement: Existing runtime enters update mode
The worker runtime init flow SHALL treat an existing `.asdlc_worker` directory as update mode and SHALL overwrite only generated runtime paths.

#### Scenario: Update overwrites generated runtime paths
- **WHEN** `.asdlc_worker` already exists
- **THEN** init SHALL overwrite `.asdlc_worker/scripts`
- **AND** it SHALL overwrite `.asdlc_worker/scripts/helpers`
- **AND** it SHALL overwrite `.asdlc_worker/golden_examples`
- **AND** it SHALL overwrite `.asdlc_worker/setup`
- **AND** it SHALL overwrite `.asdlc_worker/templates`
- **AND** it SHALL overwrite `.asdlc_worker/logs`
- **AND** it SHALL overwrite `.asdlc_worker/prompts`
- **AND** it SHALL overwrite `.asdlc_worker/AI_DEVELOPMENT_PROCESS.md`

#### Scenario: Update preserves non-generated runtime state
- **WHEN** `.asdlc_worker` already exists and contains files outside the generated update set
- **THEN** init SHALL preserve those files and directories
- **AND** it SHALL NOT delete local binding or feature-sync state files outside the generated update set

### Requirement: Generated runtime paths are excluded locally from git
The worker runtime init flow SHALL add generated runtime-only paths to the target repo's `.git/info/exclude` idempotently.

#### Scenario: Exclude entries are added
- **WHEN** init installs or updates `.asdlc_worker`
- **THEN** `.git/info/exclude` SHALL contain `.asdlc_worker/scripts`
- **AND** it SHALL contain `.asdlc_worker/scripts/helpers`
- **AND** it SHALL contain `.asdlc_worker/golden_examples`
- **AND** it SHALL contain `.asdlc_worker/setup`
- **AND** it SHALL contain `.asdlc_worker/templates`
- **AND** it SHALL contain `.asdlc_worker/logs`
- **AND** it SHALL contain `.asdlc_worker/prompts`
- **AND** it SHALL contain `.asdlc_worker/AI_DEVELOPMENT_PROCESS.md`

#### Scenario: Exclude entries are not duplicated
- **WHEN** init runs more than once for the same target repo
- **THEN** each generated runtime exclude entry SHALL appear no more than once in `.git/info/exclude`

### Requirement: Runtime scripts reject unsupported layouts
Worker runtime scripts SHALL only run from `<worker-repo>/.asdlc_worker/scripts` or its helper subtree.

#### Scenario: Script runs from copied worker runtime
- **WHEN** a worker script runs from `<worker-repo>/.asdlc_worker/scripts`
- **THEN** it SHALL resolve `.asdlc_worker` as runtime home
- **AND** it SHALL resolve the parent of `.asdlc_worker` as worker repo root

#### Scenario: Script runs from YASDEF source layout
- **WHEN** a worker script runs from the YASDEF source repository layout instead of `.asdlc_worker`
- **THEN** it SHALL exit non-zero with a meaningful unsupported-layout message
