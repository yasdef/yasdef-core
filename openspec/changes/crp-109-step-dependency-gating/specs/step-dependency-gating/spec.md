## ADDED Requirements

### Requirement: Dep satisfaction is determined by fully-checked bullet state
The orchestrator SHALL consider a step's dependencies satisfied only when every `- [ ]`/`- [x]` bullet in each dep step's block is `[x]`.

#### Scenario: Dep step is fully checked
- **WHEN** a dep step block contains at least one bullet and all bullets are `[x]`
- **THEN** that dep is considered satisfied

#### Scenario: Dep step has one or more unchecked bullets
- **WHEN** a dep step block contains at least one `- [ ]` bullet
- **THEN** that dep is NOT considered satisfied and the dependent step is skipped during selection

### Requirement: Missing or none Depends-on line means no dependencies
The orchestrator SHALL treat a step block that has no `#### Depends on:` line, or whose `#### Depends on:` value is `none`, as having no dependencies and always eligible (subject to assignment and bullet state).

#### Scenario: No Depends on line present
- **WHEN** a step block contains no `#### Depends on:` line
- **THEN** the step is eligible for selection without any dep check

#### Scenario: Depends on: none
- **WHEN** a step block contains `#### Depends on: none`
- **THEN** the step is eligible for selection without any dep check

### Requirement: Unknown dep id is a plan error
The orchestrator SHALL fail fast with a non-zero exit when a `#### Depends on:` value references a step id that does not exist anywhere in the plan.

#### Scenario: Referenced dep step id not found in plan
- **WHEN** `#### Depends on:` lists a step id and no `### Step <id>` block exists in the plan
- **THEN** orchestrator exits non-zero with an explicit plan-error message identifying the missing dep id
- **THEN** orchestrator does NOT select any step or start any phase

### Requirement: Zero-bullet dep step is a plan error
The orchestrator SHALL fail fast with a non-zero exit when a referenced dep step block exists but contains zero `- [ ]`/`- [x]` bullets.

#### Scenario: Dep step block has no bullets
- **WHEN** `#### Depends on:` lists a step id whose block exists but contains no checkbox bullets
- **THEN** orchestrator exits non-zero with an explicit plan-error message identifying the zero-bullet dep step
- **THEN** orchestrator does NOT select any step or start any phase

### Requirement: Blocked worker exits non-zero with identifying message
The orchestrator SHALL exit non-zero with a `blocked by <dep-id>` message when all assigned steps with remaining work have at least one unsatisfied dep.

#### Scenario: All assigned steps blocked
- **WHEN** one or more assigned steps have unchecked bullets but every such step has at least one unsatisfied dep
- **THEN** orchestrator exits non-zero
- **THEN** the exit message includes `blocked by` and the dep id of the first unsatisfied dep encountered

#### Scenario: At least one assigned step unblocked
- **WHEN** at least one assigned step has unchecked bullets and all its deps are satisfied
- **THEN** orchestrator selects that step normally and does not emit a blocked message

### Requirement: Multiple deps in Depends-on are comma-separated
The orchestrator SHALL parse the `#### Depends on:` value as a comma-separated list of step ids and SHALL check satisfaction for every id in the list.

#### Scenario: All listed deps satisfied
- **WHEN** `#### Depends on:` lists multiple step ids and every one is fully `[x]`
- **THEN** the step is eligible for selection

#### Scenario: One dep in list is not satisfied
- **WHEN** `#### Depends on:` lists multiple step ids and at least one is not fully `[x]`
- **THEN** the step is skipped; the unsatisfied dep id is reported if no other step is available
