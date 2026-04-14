## ADDED Requirements

### Requirement: Bootstrap script initializes overmind branch state
The system SHALL provide an executable bootstrap script that creates branch `overmind` when absent and checks out branch `overmind` when it already exists.

#### Scenario: Create branch when missing
- **WHEN** the operator runs the bootstrap script in a git repository where branch `overmind` does not exist
- **THEN** the script creates branch `overmind` and leaves the repository on that branch

#### Scenario: Reuse existing branch
- **WHEN** the operator runs the bootstrap script in a git repository where branch `overmind` already exists
- **THEN** the script checks out branch `overmind` without recreating or resetting it

### Requirement: Bootstrap script scaffolds worker registry file
The system SHALL create `overmind/worker_registry.yaml` with minimal coordination metadata only when the file is missing.

#### Scenario: Scaffold file is created on first run
- **WHEN** the operator runs the bootstrap script and `overmind/worker_registry.yaml` is absent
- **THEN** the script creates `overmind/worker_registry.yaml` containing scaffold metadata and an empty workers list

#### Scenario: Existing registry is preserved
- **WHEN** the operator runs the bootstrap script and `overmind/worker_registry.yaml` already exists
- **THEN** the script does not overwrite the existing file content

### Requirement: Bootstrap script configures remote tracking for overmind branch
The system SHALL push branch `overmind` to the configured remote repository and set upstream tracking on successful bootstrap.

#### Scenario: Push with upstream succeeds
- **WHEN** the operator runs the bootstrap script in a valid git repository with an available remote
- **THEN** the script executes push for branch `overmind` and configures upstream tracking for subsequent pulls/pushes

### Requirement: Bootstrap script fails fast on missing git prerequisites
The system SHALL fail with a non-zero exit and meaningful error message when required git prerequisites are not satisfied.

#### Scenario: Not a git repository
- **WHEN** the operator runs the bootstrap script outside a git repository
- **THEN** the script exits non-zero and prints an explicit message that git repository context is required

#### Scenario: Remote repository is missing
- **WHEN** the operator runs the bootstrap script in a git repository with no configured remote
- **THEN** the script exits non-zero and prints an explicit message that a remote repository is required

### Requirement: Bootstrap script is idempotent for repeated runs
The system SHALL allow repeated successful execution without destructive side effects on branch state or existing registry content.

#### Scenario: Repeated run remains stable
- **WHEN** the operator runs the bootstrap script multiple times with the same repository state
- **THEN** each run completes without deleting branch history or rewriting existing `overmind/worker_registry.yaml`
