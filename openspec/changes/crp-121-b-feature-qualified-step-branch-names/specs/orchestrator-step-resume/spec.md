## ADDED Requirements

### Requirement: Phase completion detection uses feature-qualified branch names when a feature is selected
When evaluating phase completion during resume and a feature is selected, the orchestrator SHALL check for feature-qualified step branches (e.g., `step-<N>-<feature-id>-implementation`) rather than step-only branch names.

#### Scenario: Implementation completion detected via feature-qualified branch
- **WHEN** resume evaluates step N with selected feature `auth-system` and branch `step-N-auth-system-implementation` exists locally
- **THEN** orchestrator marks the implementation phase as complete

#### Scenario: User-review completion detected via feature-qualified branch
- **WHEN** resume evaluates step N with selected feature `auth-system` and branch `step-N-auth-system-user-review` exists locally
- **THEN** orchestrator marks the user-review phase as complete

#### Scenario: Standalone step resume detection unchanged
- **WHEN** resume evaluates a step with no selected feature (`SELECTED_FEATURE_ID` is empty)
- **THEN** orchestrator checks for `step-<N>-implementation` and `step-<N>-user-review` using the existing step-only naming

#### Scenario: Resume does not falsely complete implementation from wrong-feature branch
- **WHEN** resume evaluates step N with selected feature `auth-system` and only `step-N-other-feature-implementation` exists (different feature)
- **THEN** orchestrator does not mark the implementation phase as complete based on the other feature's branch
