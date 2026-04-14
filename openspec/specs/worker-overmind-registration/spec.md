## ADDED Requirements

### Requirement: Worker identity file is created and reused
The worker init flow SHALL create a durable local worker identity file under `ai/` on first run using filename pattern `<uuid>_dont_touch.txt`, and SHALL reuse the same identifier on subsequent runs.

#### Scenario: First run creates worker identity artifact
- **WHEN** the worker init script runs in a valid git repository and no worker identity file matching `ai/*_dont_touch.txt` exists
- **THEN** the script creates exactly one identity file in `ai/` named `<uuid>_dont_touch.txt` and stores the same non-empty UUID in the file content

#### Scenario: Re-run preserves existing worker identity
- **WHEN** the worker init script runs and exactly one valid worker identity file matching `ai/*_dont_touch.txt` already exists
- **THEN** the script reuses the existing identifier and does not create a second identity file

#### Scenario: Coordinator planning artifacts are not bootstrapped by worker init
- **WHEN** the worker init script completes successfully
- **THEN** no new `implementation_plan.md` or `reqirements_ears.md` artifact is created under `ai/` by this flow

### Requirement: Worker init fails fast when orchestrator branch is unavailable
The worker init flow SHALL verify remote orchestrator availability by fetching or pulling branch `overmind` before registration, and SHALL fail fast with a deterministic message when unavailable.

#### Scenario: Remote overmind branch missing or unreachable
- **WHEN** the worker init script cannot fetch or pull remote branch `overmind`
- **THEN** it exits with non-zero status and prints exactly `no orchestrator detected, unable to proceed`

### Requirement: Worker is registered idempotently in coordinator registry
On successful orchestrator detection, the worker init flow SHALL switch to branch `overmind`, ensure the worker ID exists exactly once in `overmind/worker_registry.yaml` `workers` list, and push the change to remote.

#### Scenario: Worker not yet registered
- **WHEN** worker ID is absent in `overmind/worker_registry.yaml` on `overmind`
- **THEN** the script adds the worker ID, commits the registry change, and pushes to remote `overmind`

#### Scenario: Worker already registered
- **WHEN** worker ID is already present in `overmind/worker_registry.yaml` on `overmind`
- **THEN** the script does not add a duplicate worker entry

### Requirement: Worker init returns repository to master branch
After registration attempt and reporting, the worker init flow SHALL checkout branch `master`.

#### Scenario: Successful registration completes
- **WHEN** worker registration flow succeeds
- **THEN** the script reports success and checks out `master`
