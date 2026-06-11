# Capability: planning-to-implementation-readiness-gate

## Purpose
Define the planning-owned readiness gate that governs whether a step is ready to hand off into implementation.

## Requirements

### Requirement: Planning handoff MUST validate readiness through a validator exit-code contract
Planning-to-implementation readiness validation MUST be implemented through the planning skill validator at `.codex/skills/yasdef-worker-plan/scripts/check_planning_readiness.py`, which returns `0` when the planning handoff is ready and non-zero when it is not.

#### Scenario: Ready planning handoff returns success
- **WHEN** the readiness helper checks a step whose `ai/step_plans/step-<N>.md` exists, contains `## Plan (ordered)`, contains a non-empty `## Functional Requirements (translated from design EARS)` section, and whose `overmind/implementation_plan.md` `Plan and discuss the step` bullet is `[x]`
- **THEN** the helper exits with code `0`

#### Scenario: Missing planning artifact or closed gate returns failure
- **WHEN** the readiness helper checks a step whose step plan is missing, whose required planning sections are missing, or whose `Plan and discuss the step` bullet is missing or unchecked
- **THEN** the helper exits non-zero and reports the failing condition

### Requirement: Planning MUST run readiness validation before the completion line
`ai/codex/skills/yasdef-worker-plan/SKILL.md` MUST instruct the model to run the planning readiness validator immediately before the final planning completion-line guidance.

#### Scenario: Helper instruction appears before planning completion-line guidance
- **WHEN** the `yasdef-worker-plan` skill instructions are loaded for a planning iteration
- **THEN** they include a concise instruction to run `.codex/skills/yasdef-worker-plan/scripts/check_planning_readiness.py --design ... --step-plan ... --open-questions ... --blockers ...` before the planning completion-line instruction

#### Scenario: Ready planning handoff may emit the completion line
- **WHEN** the model runs the helper during planning completion and the helper exits `0`
- **THEN** the planning phase may emit the standard completion line

#### Scenario: Unready planning handoff must not emit the completion line
- **WHEN** the model runs the helper during planning completion and the helper exits non-zero
- **THEN** the planning phase does not emit the standard completion line yet

### Requirement: Implementation entry MUST require completed planning artifacts
The orchestrator implementation phase MUST fail fast before starting the model when the selected step plan, design artifact, implementation skill context script, or implementation skill readiness script is missing.

#### Scenario: Missing implementation skill runtime fails implementation immediately
- **WHEN** the orchestrator implementation phase starts and `.codex/skills/yasdef-worker-implementation` required scripts are missing
- **THEN** it exits non-zero and does not start the model

### Requirement: Planning closure failure MUST use the two-option user decision contract
When planning readiness validation fails during planning closure, the planning phase MUST ask the user to choose between continuing planning with a re-check or finishing the step immediately with failed status.

#### Scenario: Planning closure failure offers exactly two readiness options
- **WHEN** planning readiness validation fails during planning completion
- **THEN** the planning response presents exactly two options: continue planning and re-check, or finish the step immediately with failed status

#### Scenario: Planning closure failure waits for explicit user choice
- **WHEN** the planning phase presents the readiness-failure options
- **THEN** it waits for the user's reply and does not choose option `1` or `2` without explicit user input

#### Scenario: Continue-and-recheck keeps planning open
- **WHEN** the user chooses to continue planning after a readiness failure
- **THEN** the planning handoff remains unresolved until the helper passes on re-check and the planning phase does not emit the completion line

#### Scenario: Failed-status option ends the step immediately from planning
- **WHEN** the user chooses to finish the step with failed status after a planning-closure readiness failure
- **THEN** the planning phase ends the step immediately with failed status
