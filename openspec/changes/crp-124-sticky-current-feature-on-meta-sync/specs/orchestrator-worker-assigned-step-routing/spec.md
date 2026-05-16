## ADDED Requirements

### Requirement: Ordinary startup does not silently switch away from a valid current feature
During startup and re-run flows (non-resume), if `.asdlc_worker/feature_meta_sync.yaml` is present and passes reuse validation (identity match against the binding file AND derived bound-source plan and ears exist), the orchestrator SHALL NOT switch to a different feature via slow-path discovery. If the valid current feature is blocked or exhausted, the orchestrator SHALL fail fast with an explicit error.

#### Scenario: Ordinary startup reuses valid current feature
- **WHEN** the orchestrator starts in default mode without `--resume` and `.asdlc_worker/feature_meta_sync.yaml` passes reuse validation and the stored feature has a runnable step for this worker
- **THEN** the orchestrator uses the stored feature without running slow-path candidate discovery

#### Scenario: Ordinary startup fails fast on blocked current feature
- **WHEN** the orchestrator starts and `.asdlc_worker/feature_meta_sync.yaml` passes reuse validation but plan analysis returns empty `first_unchecked` with non-empty `blocked_by`
- **THEN** the orchestrator exits non-zero with an error naming the current feature and the blocking step
- **THEN** the orchestrator does not scan other features under the bound project

#### Scenario: Ordinary startup fails fast on exhausted current feature
- **WHEN** the orchestrator starts and `.asdlc_worker/feature_meta_sync.yaml` passes reuse validation but plan analysis returns empty `first_unchecked` with empty `blocked_by`
- **THEN** the orchestrator exits non-zero with an error naming the current feature as exhausted and instructing removal of `.asdlc_worker/feature_meta_sync.yaml`
- **THEN** the orchestrator does not scan other features under the bound project
