## ADDED Requirements

### Requirement: Routed step execution passes feature identity to all phase scripts
When the orchestrator routes an assigned step to a phase script and a feature is selected, the orchestrator SHALL supply the selected feature identity to that phase script so that all step branches created during execution are feature-qualified.

#### Scenario: Planning phase invocation includes feature-qualified branch name
- **WHEN** orchestrator runs the planning phase for an assigned step under selected feature `auth-system`
- **THEN** orchestrator passes the feature-qualified branch name (e.g., `step-N-auth-system-plan`) to `ai_plan.sh` via `--branch-name`

#### Scenario: Implementation phase invocation includes feature identity
- **WHEN** orchestrator runs the implementation phase for an assigned step under selected feature `auth-system`
- **THEN** orchestrator passes the feature identity to `ai_implementation.sh` so it creates branch `step-N-auth-system-implementation`

#### Scenario: User-review phase invocation includes feature identity
- **WHEN** orchestrator runs the user-review phase for an assigned step under selected feature `auth-system`
- **THEN** orchestrator passes the feature identity to `ai_user_review.sh` so it creates and references feature-qualified branch names

#### Scenario: Ai-audit phase invocation includes feature identity
- **WHEN** orchestrator runs the ai-audit phase for an assigned step under selected feature `auth-system`
- **THEN** orchestrator passes the feature identity to `ai_audit.sh` so it creates and references feature-qualified branch names

#### Scenario: No feature identity passed for standalone step routing
- **WHEN** orchestrator routes a standalone step (no selected feature) to any phase script
- **THEN** orchestrator does not pass a feature identity and phase scripts use the existing `step-<N>-<phase>` naming

### Requirement: Fast-path context detection uses feature-qualified plan branch name
When a feature is selected, the orchestrator fast-path check for an existing plan branch SHALL look for the feature-qualified branch name rather than the step-only name.

#### Scenario: Fast path detects existing feature-qualified plan branch
- **WHEN** orchestrator fast-path checks for an existing plan branch for step N under selected feature `auth-system`
- **THEN** orchestrator checks for `refs/heads/step-N-auth-system-plan` rather than `refs/heads/step-N-plan`
