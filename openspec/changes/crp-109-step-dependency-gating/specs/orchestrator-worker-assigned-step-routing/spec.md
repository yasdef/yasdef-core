## MODIFIED Requirements

### Requirement: Next work item is filtered by assigned worker UUID
The orchestrator SHALL select the next work item only from step blocks whose assignment header is `#### Assigned: <uuid>` matching the resolved worker UUID AND whose dependency satisfaction check passes. A step whose `#### Depends on:` references any dep step that is not fully `[x]` SHALL be excluded from selection regardless of its own bullet state.

#### Scenario: Assigned step has free bullet and no deps
- **WHEN** at least one step block assigned to local UUID contains unchecked bullets and has no `#### Depends on:` line or `Depends on: none`
- **THEN** orchestrator selects the first unchecked bullet from the first such assigned step block

#### Scenario: Assigned step has free bullet and all deps satisfied
- **WHEN** at least one step block assigned to local UUID contains unchecked bullets and every dep id listed in its `#### Depends on:` is fully `[x]`
- **THEN** orchestrator selects the first unchecked bullet from the first such assigned step block

#### Scenario: Assigned step has free bullet but dep is not satisfied
- **WHEN** an assigned step has unchecked bullets but at least one dep id in its `#### Depends on:` is not fully `[x]`
- **THEN** orchestrator skips that step during selection

#### Scenario: Unassigned or differently assigned step contains free bullet
- **WHEN** unchecked bullets exist in step blocks not assigned to local UUID
- **THEN** orchestrator ignores those bullets during next-step selection

### Requirement: Missing worker assignments fail fast
The orchestrator SHALL fail fast when no step blocks in `implementation_plan.md` are assigned to the resolved worker UUID.

#### Scenario: No assigned steps for worker
- **WHEN** orchestrator parses `implementation_plan.md` and finds no `#### Assigned: <uuid>` block matching local worker UUID
- **THEN** orchestrator exits non-zero with an explicit fail-fast error and does not start design or implementation

#### Scenario: Assigned steps complete with no free bullets
- **WHEN** assigned step blocks exist for local worker UUID but all bullets are complete
- **THEN** orchestrator reports no available work for this worker and exits without starting a new step

#### Scenario: Assigned steps exist but all are blocked by unsatisfied deps
- **WHEN** assigned step blocks exist for local worker UUID, at least one has unchecked bullets, but every such step has at least one unsatisfied dep
- **THEN** orchestrator exits non-zero with a `blocked by <dep-id>` message and does not start any phase
