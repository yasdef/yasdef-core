## MODIFIED Requirements

### Requirement: Ordered step plan is the execution state machine
For each step, Implementation and User Review phases MUST use only the step plan's `## Plan (ordered)` bullets as executable state. The step plan artifact path SHALL be feature-qualified (`step_plans/step-<N>-<feature-id>.md`) when a feature is selected, or step-only (`step_plans/step-<N>.md`) when no feature is selected.

#### Scenario: Implementation reads only ordered plan bullets for execution state
- **WHEN** Implementation resolves the current step execution checklist
- **THEN** it reads `## Plan (ordered)` from the feature-qualified step plan (e.g., `step_plans/step-N-auth-system.md` when feature `auth-system` is selected) and does not use `implementation_plan.md` target bullets as phase state

#### Scenario: User Review reads only ordered plan bullets for precheck state
- **WHEN** User Review precheck validates readiness for review-loop execution
- **THEN** it validates `## Plan (ordered)` bullet state from the feature-qualified step plan only

### Requirement: Ordered plan bullets are checkbox-tracked lifecycle items
Each `## Plan (ordered)` bullet MUST be represented as a checkbox (`[ ]` or `[x]`) and MUST transition to `[x]` only after that specific bullet is proven complete.

#### Scenario: Unimplemented bullet remains unchecked
- **WHEN** a bullet has not completed implementation and verification gates
- **THEN** the bullet remains `[ ]` in the step plan artifact

#### Scenario: Proven bullet is marked complete
- **WHEN** implementation and verification for a specific bullet are complete with concrete evidence
- **THEN** that bullet is updated to `[x]` in the step plan artifact

### Requirement: Implementation executes ordered bullets one-by-one
Implementation MUST process unchecked `## Plan (ordered)` bullets sequentially and MUST complete each bullet's implementation and verification before moving to the next unchecked bullet.

#### Scenario: Sequential bullet closure is enforced
- **WHEN** multiple unchecked ordered bullets exist
- **THEN** Implementation closes the first unchecked bullet before starting implementation work for the next unchecked bullet

#### Scenario: User review is not entered per bullet
- **WHEN** one ordered bullet is completed but other ordered bullets remain unchecked
- **THEN** Implementation continues the sequential loop and does not enter User Review until implementation-phase completion criteria are met

### Requirement: Implementation reporting aligns to ordered bullets
Implementation and User Review outputs MUST report progress and completion evidence against `## Plan (ordered)` bullets rather than `implementation_plan.md` target bullets.

#### Scenario: Completion report references ordered bullet IDs/text
- **WHEN** the model emits implementation completion reporting for a step
- **THEN** the report maps evidence to `## Plan (ordered)` bullets and does not present `implementation_plan.md` target bullets as implementation-phase completion state
