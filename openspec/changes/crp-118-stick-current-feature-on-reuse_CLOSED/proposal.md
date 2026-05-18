## Why

The current selected-feature state is treated as a hint instead of an authoritative in-progress context. When the selected feature is still valid but blocked or fully consumed, orchestrator can silently fall through into global discovery and switch to a different feature, which breaks determinism and hides the real reason the current feature cannot continue.

## What Changes

- Treat a valid `feature_sync.yaml` selection as sticky current-feature context rather than an advisory optimization.
- Split current-feature reuse outcomes into explicit states:
  - stale or invalid selection may be reselected,
  - valid but blocked selection fails fast with a blocker message,
  - valid but fully complete selection fails fast with a no-runnable-step message.
- Remove the current fallback where a valid-but-unrunnable selected feature silently drops into global candidate discovery.
- Require rerouting to another feature to happen only after explicit user intent or after the stored current feature is proven stale.

## Capabilities

### New Capabilities
- `sticky-current-feature-routing`: Orchestrator keeps a valid selected feature as the active run context and reports blocked or complete status explicitly instead of silently choosing another feature.

### Modified Capabilities
- `orchestrator-step-resume`: Resume reuses a valid selected feature as authoritative context and fails fast when that feature is blocked or exhausted instead of rediscovering another feature.
- `orchestrator-worker-assigned-step-routing`: Next-step routing no longer silently switches away from a valid current feature during ordinary startup or rerun flows.

## Impact

- Affected runtime script:
  - `ai/scripts/orchestrator.sh`
- Affected tests:
  - `tests/ai_scripts/orchestrator_assignment_tests.sh`
  - `tests/ai_scripts/orchestrator_resume_tests.sh`
- Affected docs/spec references:
  - `Readme.md`
  - selected-feature routing and reuse requirements in OpenSpec artifacts
