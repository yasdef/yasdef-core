## Why

Current orchestrator step branches are named only by step number, which becomes ambiguous when the same worker touches identical step numbers across multiple features. Branch names need feature identity embedded so operators and tooling can distinguish work contexts reliably across parallel feature flows.

## What Changes

- Change orchestrator-created step branch names so they append the selected feature name after the step identifier.
- Apply the feature-qualified branch naming consistently across planning, implementation, user-review, and ai-audit step branches.
- Update any branch-detection or resume logic that currently assumes step-only branch names.
- Preserve the step number as the primary routing key; the feature suffix improves uniqueness and operator readability.

## Capabilities

### New Capabilities
- `feature-qualified-step-branch-names`: Orchestrator-created step branches include selected feature identity so branch names are unique across features sharing the same step number.

### Modified Capabilities
- `orchestrator-worker-assigned-step-routing`: Routed step execution creates and recognizes feature-qualified branch names instead of step-only branch names.
- `orchestrator-step-resume`: Resume logic recognizes the updated branch naming convention when locating current-step context and later-phase markers.

## Impact

- Affected runtime script:
  - `ai/scripts/orchestrator.sh`
- Likely affected phase/helper scripts:
  - scripts or helpers that parse `step-<N>-...` branch names
- Affected tests:
  - `tests/ai_scripts/orchestrator_resume_tests.sh`
  - `tests/ai_scripts/orchestrator_assignment_tests.sh`
  - any tests asserting exact step-branch names
- Affected docs/spec references:
  - `Readme.md`
  - operator-facing branch examples in process docs
