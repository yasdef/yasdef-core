## ADDED Requirements

### Requirement: Coordinator artifacts SHALL be boundary inputs only
The workflow SHALL treat `overmind/implementation_plan.md` and `overmind/reqirements_ears.md` as direct inputs only at design entry and ai_audit exit boundaries.

#### Scenario: Design consumes coordinator artifacts directly
- **WHEN** design context is assembled for a step
- **THEN** the workflow reads target bullets from `overmind/implementation_plan.md` and selected EARS blocks from `overmind/reqirements_ears.md`

#### Scenario: ai_audit entry proof-check uses coordinator targets
- **WHEN** ai_audit executes Section 6.0 entry proof-check
- **THEN** proof status is evaluated against current-step target bullets from `overmind/implementation_plan.md`

### Requirement: Mid phases SHALL not use implementation_plan target bullets as execution state
Planning, implementation, and user_review SHALL use step-plan ordered execution artifacts and SHALL NOT use `implementation_plan.md` target bullets as phase state machine.

#### Scenario: Planning does not emit target-bullet execution checklist
- **WHEN** planning generates or updates step plan execution content
- **THEN** it does not define execution state using `## Target Bullets`

#### Scenario: Implementation and user_review execute ordered plan contract
- **WHEN** implementation and user_review process step progress
- **THEN** they reference ordered bullets and translated functional requirements from step plan rather than target bullets in `implementation_plan.md`

### Requirement: Section 4 verification gate SHALL enforce step-plan requirement completion before user_review
The phase transition from implementation to user_review SHALL be controlled by Section `### 4) Verification gates (required before Section 5)` using step-plan translated functional requirements rather than direct coordinator-artifact state.

#### Scenario: Section 4 fails if translated functional requirements are not complete
- **WHEN** verification gate runs before Section 5 and one or more translated functional requirements are incomplete
- **THEN** the workflow blocks transition to user_review and remains in implementation closure

#### Scenario: Section 4 passes using translated functional requirement completion and evidence
- **WHEN** verification gate runs before Section 5 and all translated functional requirements are complete with verification evidence
- **THEN** workflow allows transition to user_review without consulting `implementation_plan.md` as execution state

### Requirement: Process and repository documentation SHALL describe one boundary model
Core process documentation and README SHALL describe the same phase-boundary contract without contradictions.

#### Scenario: Process doc states boundary-only coordinator artifact usage
- **WHEN** operators read `ai/AI_DEVELOPMENT_PROCESS.md`
- **THEN** it explicitly states design+ai_audit boundary use of coordinator artifacts and mid-phase execution contract

#### Scenario: README repeats the same core concept
- **WHEN** operators read `Readme.md`
- **THEN** it documents that design+ai_audit use coordinator artifacts, while plan/implementation/user_review use ordered plan + translated functional requirements
