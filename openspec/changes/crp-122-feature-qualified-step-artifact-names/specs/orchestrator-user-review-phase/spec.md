## ADDED Requirements

### Requirement: User-review phase reads and writes feature-qualified step artifacts when a feature is selected
When the user-review phase executes under a selected feature, it SHALL resolve the step plan from the feature-qualified path (`step_plans/step-<N>-<feature-id>.md`) and SHALL NOT fall back to the step-only path for plan resolution.

#### Scenario: User-review resolves feature-qualified step plan
- **WHEN** user-review phase runs for step N under selected feature `auth-system`
- **THEN** user-review reads the step plan from `step_plans/step-N-auth-system.md`

#### Scenario: User-review fails fast when feature-qualified step plan is missing
- **WHEN** user-review phase runs for step N under selected feature `auth-system` and `step_plans/step-N-auth-system.md` does not exist
- **THEN** user-review exits with an explicit error and does not silently fall back to `step_plans/step-N.md`
