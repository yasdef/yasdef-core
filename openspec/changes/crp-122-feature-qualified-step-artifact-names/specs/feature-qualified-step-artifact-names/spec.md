## ADDED Requirements

### Requirement: Step artifact filenames include selected feature identity when a feature is active
When the orchestrator executes a step under a selected feature, per-step artifacts SHALL use feature-qualified filenames: `step-<N>-<feature-id>.md` for step plans, `step-<N>-<feature-id>-design.md` for step designs, and `review_result-<N>-<feature-id>.md` for review results. When no feature is selected, artifact filenames SHALL remain `step-<N>.md`, `step-<N>-design.md`, and `review_result-<N>.md`.

#### Scenario: Step plan written with feature identity
- **WHEN** orchestrator runs the planning phase for step N under selected feature `auth-system`
- **THEN** the step plan is written to `step_plans/step-N-auth-system.md`

#### Scenario: Step design written with feature identity
- **WHEN** orchestrator runs the design phase for step N under selected feature `auth-system`
- **THEN** the step design is written to `step_designs/step-N-auth-system-design.md`

#### Scenario: Review result written with feature identity
- **WHEN** orchestrator runs the ai-audit phase for step N under selected feature `auth-system`
- **THEN** the review result is written to `step_review_results/review_result-N-auth-system.md`

#### Scenario: Standalone step artifacts are not feature-qualified
- **WHEN** orchestrator executes a step with no selected feature (`SELECTED_FEATURE_ID` is empty)
- **THEN** artifact filenames use the existing step-only naming without a feature qualifier

### Requirement: Phase scripts produce feature-qualified artifact paths when feature ID is supplied
Each phase script (`ai_plan.sh`, `ai_implementation.sh`, `ai_user_review.sh`, `ai_audit.sh`) SHALL accept a mechanism to receive the feature identity and SHALL use it to qualify all step artifact paths it creates or reads within that invocation.

#### Scenario: ai_plan.sh writes feature-qualified step plan
- **WHEN** `ai_plan.sh` is invoked with feature identity `auth-system` for step N
- **THEN** it writes the step plan to `step_plans/step-N-auth-system.md`

#### Scenario: ai_implementation.sh reads feature-qualified step plan
- **WHEN** `ai_implementation.sh` is invoked with feature identity `auth-system` for step N
- **THEN** it reads the step plan from `step_plans/step-N-auth-system.md`

#### Scenario: ai_audit.sh writes feature-qualified review result
- **WHEN** `ai_audit.sh` is invoked with feature identity `auth-system` for step N
- **THEN** it writes the review result to `step_review_results/review_result-N-auth-system.md`

### Requirement: Step extraction from feature-qualified artifact filenames returns only the step number
Helpers that extract the step number from a feature-qualified artifact filename (e.g., `get_step_from_plan_path`, `get_step_from_design_path`) SHALL return only the numeric step component and SHALL NOT include the feature ID in the returned value.

#### Scenario: Step extracted from feature-qualified plan filename
- **WHEN** the plan filename is `step-2-auth-system.md`
- **THEN** step extraction returns `2`

#### Scenario: Step extracted from feature-qualified design filename
- **WHEN** the design filename is `step-2-auth-system-design.md`
- **THEN** step extraction returns `2`

#### Scenario: Step extracted from standalone plan filename is unchanged
- **WHEN** the plan filename is `step-2.md`
- **THEN** step extraction returns `2`

### Requirement: Latest step plan lookup filters by feature identity when a feature is active
When resolving the latest step plan and a feature is selected, the lookup SHALL match only feature-qualified plans for that feature. When no feature is selected, the lookup SHALL match only step-only plans.

#### Scenario: Latest plan resolved to feature-qualified file
- **WHEN** step plan directory contains `step-1-auth-system.md` and `step-2-auth-system.md` and selected feature is `auth-system`
- **THEN** `get_latest_step_plan` returns `step-2-auth-system.md`

#### Scenario: Feature-qualified files are excluded from standalone latest resolution
- **WHEN** step plan directory contains `step-1.md`, `step-2-auth-system.md` and no feature is selected
- **THEN** `get_latest_step_plan` returns `step-1.md` and does not consider `step-2-auth-system.md`
