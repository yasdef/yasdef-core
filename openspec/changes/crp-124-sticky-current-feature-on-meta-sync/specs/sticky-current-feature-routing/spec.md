## ADDED Requirements

### Requirement: Valid current feature is sticky
When `.asdlc_worker/feature_meta_sync.yaml` is present and passes reuse validation (identity match against the binding file AND derived bound-source plan and ears exist), the orchestrator SHALL treat the stored feature as the authoritative active context and SHALL NOT fall through to slow-path global candidate discovery. Slow-path discovery SHALL only run when no `feature_meta_sync.yaml` exists or when reuse validation fails (project_id/worker_uuid mismatch, missing bound-source plan, empty bound-source ears, or `--resume <step>` not assigned to this worker).

#### Scenario: Valid feature with runnable step proceeds normally
- **WHEN** `.asdlc_worker/feature_meta_sync.yaml` is present, reuse validation succeeds, and the stored feature has at least one unchecked assigned step for this worker
- **THEN** the orchestrator uses that feature and step without running slow-path discovery

#### Scenario: Stale metadata allows slow-path discovery
- **WHEN** `.asdlc_worker/feature_meta_sync.yaml` is present but reuse validation fails (project_id mismatch, worker_uuid mismatch, missing derived plan, or empty derived ears)
- **THEN** the orchestrator discards the stored context and runs slow-path candidate discovery as normal

#### Scenario: Missing metadata allows slow-path discovery
- **WHEN** no `.asdlc_worker/feature_meta_sync.yaml` file exists
- **THEN** the orchestrator runs slow-path candidate discovery as normal

### Requirement: Valid but blocked current feature fails fast
When `.asdlc_worker/feature_meta_sync.yaml` passes reuse validation but plan analysis for this worker returns an empty `first_unchecked` and a non-empty `blocked_by`, the orchestrator SHALL fail fast with an explicit error naming the current feature and the blocking step. The orchestrator MUST NOT silently switch to a different feature.

#### Scenario: Valid feature blocked by prerequisite fails fast
- **WHEN** `.asdlc_worker/feature_meta_sync.yaml` is present, reuse validation succeeds, and plan analysis returns empty `first_unchecked` with non-empty `blocked_by`
- **THEN** the orchestrator exits non-zero with an error message naming the current feature and the blocking step
- **THEN** the orchestrator does not run slow-path candidate discovery

#### Scenario: Blocked-feature error message names blocking step
- **WHEN** the orchestrator fails fast because the current feature is blocked
- **THEN** the error message includes both the current feature ID and the name of the step blocking progress

### Requirement: Valid but exhausted current feature fails fast
When `.asdlc_worker/feature_meta_sync.yaml` passes reuse validation but plan analysis for this worker returns an empty `first_unchecked` and an empty `blocked_by` (i.e., the feature has assigned bullets but they are all complete), the orchestrator SHALL fail fast with an explicit error naming the current feature as exhausted. The orchestrator MUST NOT silently switch to a different feature.

#### Scenario: Valid feature with all steps complete fails fast
- **WHEN** `.asdlc_worker/feature_meta_sync.yaml` is present, reuse validation succeeds, and plan analysis returns empty `first_unchecked` with empty `blocked_by`
- **THEN** the orchestrator exits non-zero with an error message naming the current feature as exhausted
- **THEN** the orchestrator does not run slow-path candidate discovery

#### Scenario: Exhausted-feature error message guides operator to escape
- **WHEN** the orchestrator fails fast because the current feature is exhausted
- **THEN** the error message instructs the operator to remove `.asdlc_worker/feature_meta_sync.yaml` to allow reselection
