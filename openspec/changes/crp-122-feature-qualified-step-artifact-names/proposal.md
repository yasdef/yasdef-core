## Why

Step-scoped artifacts under `.asdlc_worker/step_designs`, `.asdlc_worker/step_plans`, and `.asdlc_worker/step_review_results` are currently keyed only by step number. When multiple features reuse the same step numbers, those filenames collide conceptually and can overwrite or obscure artifacts that belong to different selected features.

## What Changes

- Change orchestrator-managed per-step artifact filenames to include the selected feature name together with the step number.
- Apply feature-qualified naming consistently to:
  - step design artifacts
  - step plan artifacts
  - step review result artifacts
- Update lookup and latest/preferred artifact resolution logic so orchestrator can find the correct feature-qualified artifact for the selected feature.
- Preserve step number semantics for phase routing while making filenames unique across features.

## Capabilities

### New Capabilities
- `feature-qualified-step-artifact-names`: Worker step artifacts include selected feature identity in their filenames so artifact paths are unique across features sharing the same step number.

### Modified Capabilities
- `orchestrator-step-resume`: Resume evaluation and phase startup locate feature-qualified step artifacts instead of assuming one artifact per step number globally.
- `orchestrator-user-review-phase`: User-review phase artifact discovery and output naming follow feature-qualified step artifact paths.
- `step-plan-ordered-execution`: Step-plan artifact addressing becomes feature-qualified while preserving the ordered-plan contract for the selected feature and step.

## Impact

- Affected runtime scripts:
  - `ai/scripts/orchestrator.sh`
  - scripts that read/write step artifact paths under `.asdlc_worker/step_*`
- Affected tests:
  - `tests/ai_scripts/orchestrator_resume_tests.sh`
  - `tests/ai_scripts/orchestrator_assignment_tests.sh`
  - tests for phase scripts that assert exact step artifact filenames
- Affected docs/spec references:
  - `Readme.md`
  - any examples referencing `step-<N>.md`, `step-<N>-design.md`, or `review_result-<N>.md`
