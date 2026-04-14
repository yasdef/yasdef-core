## ADDED Requirements

### Requirement: Overmind registry updates are committed and pushed before leaving overmind
Worker init SHALL perform registry registration on branch `overmind`, create a local commit for registry changes when needed, and push that commit to remote before switching back to `master`.

#### Scenario: Registry requires new worker entry
- **WHEN** worker ID is missing in `worker_registry.yaml` on `overmind`
- **THEN** the script creates an overmind commit containing registry update and pushes it to remote `overmind`

#### Scenario: Registry already contains worker entry
- **WHEN** worker ID is already present in `worker_registry.yaml` on `overmind`
- **THEN** the script does not add a duplicate entry and may skip overmind commit when no registry change exists

### Requirement: Worker identity file is persisted on master branch
Worker init SHALL persist worker identity on branch `master` as `ai/<uuid>_dont_touch.txt` by creating a path-scoped commit when file creation or content change is needed.

#### Scenario: First worker init run
- **WHEN** no valid worker identity file matching `ai/*_dont_touch.txt` exists on `master`
- **THEN** the script creates `ai/<uuid>_dont_touch.txt`, commits only that file on `master`, and reports commit status

#### Scenario: Subsequent run with unchanged worker identity
- **WHEN** exactly one valid worker identity file matching `ai/*_dont_touch.txt` already exists on `master` with current UUID content
- **THEN** the script reuses the same ID and skips master commit with explicit message

### Requirement: Shared and local artifacts remain branch-scoped
Worker init SHALL keep shared coordination artifact and worker-local identity artifact in their intended branches to reduce cross-worker contention and local working-tree noise.

#### Scenario: Completion state verification
- **WHEN** worker init completes successfully
- **THEN** worker registry update history is on `overmind` and `ai/<uuid>_dont_touch.txt` is durable on `master`

### Requirement: Fail-fast orchestrator detection remains unchanged
Worker init SHALL keep deterministic orchestrator detection and fail with exact required message when remote `overmind` is unavailable.

#### Scenario: Overmind unavailable
- **WHEN** script cannot fetch or pull remote branch `overmind`
- **THEN** it exits non-zero and prints exactly `no orchestrator detected, unable to proceed`
