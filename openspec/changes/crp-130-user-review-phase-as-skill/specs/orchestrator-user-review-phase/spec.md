## ADDED Requirements

### Requirement: User review is executed through an installed skill
The orchestrator MUST execute the user-review phase by writing a compact prompt that invokes the installed `yasdef-worker-user-review` skill.

#### Scenario: Compact user-review skill prompt is written
- **WHEN** user review starts with a resolved step, design artifact, and step plan
- **THEN** orchestrator writes a prompt that names `yasdef-worker-user-review`
- **AND** the prompt passes only explicit inputs: step, feature id, branch, step plan path, design artifact path, and runtime implementation plan path
- **AND** the prompt does not inline the legacy context pack

### Requirement: User review entry readiness is orchestrator-owned
Before invoking the model, the orchestrator MUST run `.codex/skills/yasdef-worker-implementation/scripts/check_implementation_readiness.py` as the hard user-review entry gate.

#### Scenario: Incomplete step blocks user review before model execution
- **WHEN** ordered-plan items or translated functional requirements remain open in the step plan
- **THEN** orchestrator exits non-zero before invoking the user-review model command
- **AND** it reports that implementation must be completed first

#### Scenario: Closed step allows user review even if runtime target bullets remain open
- **WHEN** the step plan passes implementation readiness
- **THEN** orchestrator allows user review to start based on that gate alone

### Requirement: User review branch is created from implementation
The user-review phase MUST run on `step-<step>-<feature-id>-user-review`, created or switched from `step-<step>-<feature-id>-implementation`.

#### Scenario: Missing user-review branch is created from implementation branch
- **WHEN** the user-review branch does not yet exist
- **THEN** orchestrator creates it from the implementation branch and switches to it

#### Scenario: Unsafe dirty state blocks branch handoff
- **WHEN** the current branch is not the implementation branch and the working tree has uncommitted changes
- **THEN** orchestrator exits with an actionable branch-handoff error instead of proceeding

### Requirement: User review remains single-pass
The orchestrator MUST invoke the configured user-review model command once per phase execution and MUST NOT run a user-review exit-readiness script after the model returns.

#### Scenario: Successful user-review execution advances without exit-readiness recheck
- **WHEN** the user-review model command exits successfully
- **THEN** orchestrator returns that status directly
- **AND** it does not run a second readiness script after the model exits
