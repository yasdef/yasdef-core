## ADDED Requirements

### Requirement: Step branch names include selected feature identity
When the orchestrator executes a step, orchestrator-created step branches SHALL use the form `step-<step>-<feature-id>-<phase>` where `<feature-id>` is the selected feature identifier (`SELECTED_FEATURE_ID`). Feature selection is required for every step, so `SELECTED_FEATURE_ID` is always non-empty at the point branches are created.

#### Scenario: Planning branch created with feature identity
- **WHEN** orchestrator starts the planning phase for step N under selected feature `auth-system`
- **THEN** the planning branch is created as `step-N-auth-system-plan`

#### Scenario: Implementation branch created with feature identity
- **WHEN** orchestrator starts the implementation phase for step N under selected feature `auth-system`
- **THEN** the implementation branch is created as `step-N-auth-system-implementation`

#### Scenario: User-review branch created with feature identity
- **WHEN** orchestrator starts the user-review phase for step N under selected feature `auth-system`
- **THEN** the user-review branch is created as `step-N-auth-system-user-review`

#### Scenario: Ai-audit branch created with feature identity
- **WHEN** orchestrator starts the ai-audit phase for step N under selected feature `auth-system`
- **THEN** the audit branch is created as `step-N-auth-system-review`

### Requirement: Phase scripts construct feature-qualified branch names when feature ID is supplied
Each phase script (`ai_plan.sh`, `ai_implementation.sh`, `ai_user_review.sh`, `ai_audit.sh`) SHALL accept a mechanism to receive the feature identity and SHALL use it to qualify all step branch names it creates or references within that invocation.

#### Scenario: ai_plan.sh creates feature-qualified plan branch
- **WHEN** orchestrator invokes `ai_plan.sh` with a feature-qualified branch name for step N and feature `auth-system`
- **THEN** `ai_plan.sh` creates or switches to branch `step-N-auth-system-plan`

#### Scenario: ai_implementation.sh creates feature-qualified implementation branch
- **WHEN** orchestrator invokes `ai_implementation.sh` with feature identity `auth-system` for step N
- **THEN** `ai_implementation.sh` creates or switches to branch `step-N-auth-system-implementation`

#### Scenario: ai_user_review.sh resolves feature-qualified source and target branches
- **WHEN** orchestrator invokes `ai_user_review.sh` with feature identity `auth-system` for step N
- **THEN** `ai_user_review.sh` uses `step-N-auth-system-implementation` as the source and `step-N-auth-system-user-review` as the target branch

#### Scenario: ai_audit.sh resolves feature-qualified source and target branches
- **WHEN** orchestrator invokes `ai_audit.sh` with feature identity `auth-system` for step N
- **THEN** `ai_audit.sh` uses `step-N-auth-system-user-review` (or `step-N-auth-system-implementation`) as the source and `step-N-auth-system-review` as the target branch

### Requirement: Step number extraction from branch names handles feature-qualified format
`get_step_from_branch_name()` (and equivalent helpers in phase scripts) SHALL correctly extract the step number from the feature-qualified `step-<N>-<feature-id>-<phase>` format.

#### Scenario: Step extracted from feature-qualified branch name
- **WHEN** current branch is `step-2-auth-system-implementation`
- **THEN** `get_step_from_branch_name` returns `2`
