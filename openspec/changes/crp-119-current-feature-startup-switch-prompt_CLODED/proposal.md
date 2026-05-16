## Why

Once selected-feature reuse becomes sticky, operators still need an explicit way to keep working on the current feature or switch intentionally at orchestrator startup. That decision should be visible and deterministic rather than implied by hidden fallback logic.

## What Changes

- When a valid current feature exists, prompt the operator at orchestrator startup with:
  - `1. Proceed with current feature`
  - `2. Change feature`
- If the operator chooses `Change feature`, show the normal feature picker rather than silently reusing the current feature.
- In the feature picker, place the current feature first and label it `(CURRENT)` so the operator can confirm or change context intentionally.
- If there is no valid current feature, skip the proceed/change prompt and use normal first-selection behavior.

## Capabilities

### New Capabilities
- `current-feature-startup-switch-prompt`: Orchestrator offers an explicit proceed-or-change decision whenever a valid current feature is already selected.

### Modified Capabilities
- `orchestrator-worker-assigned-step-routing`: Interactive feature selection includes an explicit current-feature handoff path instead of relying on implicit fallback or immediate reuse.

## Impact

- Affected runtime script:
  - `ai/scripts/orchestrator.sh`
- Affected tests:
  - `tests/ai_scripts/orchestrator_assignment_tests.sh`
  - `tests/ai_scripts/orchestrator_resume_tests.sh`
- Affected docs/spec references:
  - `Readme.md`
  - operator-facing orchestration flow documentation
