## REMOVED Requirements

### Requirement: Worker identity file is created and reused
**Reason**: Worker identity is no longer generated or stored as an `ai/*_dont_touch.txt` file in a root `ai/` runtime. Worker runtime installation and binding state now live under `.asdlc_worker/`.
**Migration**: Use the new init/update flow to install `.asdlc_worker/`, then bind the worker using the existing registered UUID flow stored under `.asdlc_worker/` state.

### Requirement: Worker init fails fast when orchestrator branch is unavailable
**Reason**: Worker init no longer detects a legacy remote `overmind` branch as the first registration gate. Target repo validation and `.asdlc_worker/` runtime bootstrap happen before worker/project binding.
**Migration**: Validate the target repo and runtime layout first; subsequent worker binding continues to validate the bound ASDLC project and worker registry.

### Requirement: Worker is registered idempotently in coordinator registry
**Reason**: Worker-side registration no longer mutates a coordinator registry or pushes an `overmind` branch. Worker registration remains coordinator-owned and `register_worker.sh` validates an already-registered UUID.
**Migration**: Register workers in the ASDLC project registry first, then run `.asdlc_worker/scripts/register_worker.sh` from the target repo runtime.

### Requirement: Worker init returns repository to master branch
**Reason**: The new init flow bootstraps runtime files into a target repo and does not implement the legacy branch-switch registration transaction.
**Migration**: Branch handling belongs to runtime orchestration after worker binding, using the target repo root derived from `.asdlc_worker`.

## ADDED Requirements

### Requirement: Worker registration runs from installed runtime context
`register_worker.sh` SHALL run against a target repo-local `.asdlc_worker/` runtime and SHALL NOT require or support execution from the YASDEF source checkout as the worker repo.

#### Scenario: Worker registration starts from supported runtime
- **WHEN** `register_worker.sh` runs from `<worker-repo>/.asdlc_worker/scripts`
- **THEN** it SHALL use `<worker-repo>/.asdlc_worker` for worker runtime state
- **AND** it SHALL use `<worker-repo>` for git and project-code operations

#### Scenario: Worker registration starts from unsupported source checkout
- **WHEN** `register_worker.sh` runs from a script path that is not under `<worker-repo>/.asdlc_worker/scripts`
- **THEN** it SHALL exit non-zero with a meaningful unsupported-layout message

### Requirement: Worker registration stores binding state under .asdlc_worker
`register_worker.sh` SHALL store worker-local binding state under `.asdlc_worker/` instead of root `ai/`.

#### Scenario: Worker binding succeeds
- **WHEN** `register_worker.sh` validates a registered worker UUID against the bound ASDLC project
- **THEN** it SHALL write binding metadata under `<worker-repo>/.asdlc_worker/`
- **AND** it SHALL NOT write `ai/project_overmind.yaml`
- **AND** it SHALL NOT create `ai/*_dont_touch.txt`
