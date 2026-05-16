## ADDED Requirements

### Requirement: Valid current feature is sticky
When `feature_sync.yaml` is present and passes reuse validation, the orchestrator SHALL treat the stored feature as the authoritative active context and SHALL NOT fall through to global candidate discovery. Global discovery SHALL only run when no `feature_sync.yaml` exists or when reuse validation fails (stale or invalid stored feature).

#### Scenario: Valid feature with runnable step proceeds normally
- **WHEN** `feature_sync.yaml` is present and reuse validation succeeds and the stored feature has at least one unchecked assigned step
- **THEN** the orchestrator uses that feature and step without running global discovery

#### Scenario: Stale feature allows global discovery
- **WHEN** `feature_sync.yaml` is present but reuse validation fails (project mismatch, worker mismatch, runtime branch mismatch, or missing source files)
- **THEN** the orchestrator discards the stored context and runs global candidate discovery as normal

#### Scenario: No feature_sync.yaml allows global discovery
- **WHEN** no `feature_sync.yaml` file exists
- **THEN** the orchestrator runs global candidate discovery as normal

### Requirement: Valid but blocked current feature fails fast
When `feature_sync.yaml` passes reuse validation but the stored feature's assigned step is blocked by an incomplete prerequisite step, the orchestrator SHALL fail fast with an explicit error naming the blocking step and the current feature. The orchestrator SHALL NOT silently discover a different feature.

#### Scenario: Valid feature blocked by prerequisite fails fast
- **WHEN** `feature_sync.yaml` is present and reuse validation succeeds and plan analysis shows the assigned step is blocked by an upstream step
- **THEN** the orchestrator exits non-zero with an error message naming the current feature and the blocking step
- **THEN** the orchestrator does not run global candidate discovery

#### Scenario: Error message names the blocking step
- **WHEN** the orchestrator fails fast because the current feature is blocked
- **THEN** the error message includes both the current feature ID and the name of the step blocking progress

### Requirement: Valid but exhausted current feature fails fast
When `feature_sync.yaml` passes reuse validation but all assigned checklist bullets for the stored feature are complete, the orchestrator SHALL fail fast with an explicit error stating the feature is exhausted. The orchestrator SHALL NOT silently discover a different feature.

#### Scenario: Valid feature with all steps complete fails fast
- **WHEN** `feature_sync.yaml` is present and reuse validation succeeds and plan analysis shows all assigned steps are checked
- **THEN** the orchestrator exits non-zero with an error message naming the current feature as exhausted
- **THEN** the orchestrator does not run global candidate discovery

#### Scenario: Error message guides operator to escape
- **WHEN** the orchestrator fails fast because the current feature is exhausted
- **THEN** the error message instructs the operator how to clear the stored context to allow reselection (e.g. delete or clear `feature_sync.yaml`)
