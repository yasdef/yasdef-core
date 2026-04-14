## MODIFIED Requirements

### Requirement: Worker identity file is created and reused
The worker init flow SHALL prompt the operator to provide a non-empty worker UUID and SHALL use that provided UUID as the identity to validate. It SHALL NOT generate a new UUID or reuse a legacy identity file under `ai/*_dont_touch.txt`.

#### Scenario: Operator provides worker uuid interactively
- **WHEN** the worker init script starts in a valid local worker repository
- **THEN** it SHALL ask the operator to provide a worker UUID before validation begins

#### Scenario: Legacy local worker identity file is not reused
- **WHEN** the worker init script runs and a legacy file matching `ai/*_dont_touch.txt` exists
- **THEN** the script SHALL ignore that legacy file for identity selection
- **AND** SHALL continue using the operator-provided UUID as the validation input

### Requirement: Worker init fails fast when orchestrator branch is unavailable
The worker init flow SHALL ask for the path to the overmind repo, SHALL verify that path exists, and SHALL fail fast with a meaningful message when the overmind-side worker registry source cannot be inspected.

#### Scenario: Provided overmind repo path does not exist
- **WHEN** the operator provides an overmind path that does not exist
- **THEN** the script SHALL exit non-zero
- **AND** SHALL print an error explaining that the overmind repo path was not found

#### Scenario: No project worker registries are available in overmind source
- **WHEN** the operator provides an existing overmind repo path but no project `workers.yaml` files can be found for inspection
- **THEN** the script SHALL exit non-zero
- **AND** SHALL print an error explaining that overmind worker registration data is missing

### Requirement: Worker is registered idempotently in coordinator registry
Worker init SHALL validate that the provided worker UUID is already registered in the provided overmind source and SHALL NOT modify any shared overmind registry files during this flow.

#### Scenario: Provided uuid matches one registered worker entry
- **WHEN** the provided overmind repo contains exactly one project `workers.yaml` entry whose `uuid` matches the operator-provided worker UUID
- **THEN** the script SHALL use that matched entry as the source of worker metadata for local binding
- **AND** SHALL NOT append, edit, commit, or push any overmind worker registry content

#### Scenario: Provided uuid is not registered
- **WHEN** the provided overmind repo contains no worker entry whose `uuid` matches the operator-provided worker UUID
- **THEN** the script SHALL exit non-zero
- **AND** SHALL print an error explaining that the worker UUID is not registered in the provided overmind source

#### Scenario: Provided uuid resolves ambiguously
- **WHEN** the provided overmind repo contains more than one worker entry whose `uuid` matches the operator-provided worker UUID
- **THEN** the script SHALL exit non-zero
- **AND** SHALL print an error explaining that the worker UUID resolved to multiple registrations

### Requirement: Worker init returns repository to master branch
Worker init SHALL complete local worker binding without switching branches and SHALL leave the local repository on the branch where the command started.

#### Scenario: Successful local binding preserves current branch
- **WHEN** worker init completes successfully
- **THEN** the local repository SHALL remain on the same checked-out branch that was active when the script started
