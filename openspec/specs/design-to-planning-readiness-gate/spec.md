# Capability: design-to-planning-readiness-gate

## Purpose
Define the design-owned readiness gate that governs whether a design artifact is ready to hand off into planning.

## Requirements

### Requirement: Design handoff MUST validate readiness through a helper exit-code contract
Design-to-planning readiness validation for design artifacts MUST be implemented through a helper under `ai/scripts/helpers/` that returns `0` when the design artifact is ready and non-zero when it is not ready.

#### Scenario: Ready design returns success
- **WHEN** the design readiness helper checks a design artifact that exists and contains `## Goal`, `## In Scope`, and `## Out of Scope`
- **THEN** the helper exits with code `0`

#### Scenario: Missing required sections returns failure
- **WHEN** the design readiness helper checks a design artifact that is missing one or more of `## Goal`, `## In Scope`, or `## Out of Scope`
- **THEN** the helper exits non-zero

### Requirement: Design MUST run readiness validation before the completion line
`ai/scripts/ai_design.sh` MUST instruct the model to run the design readiness helper immediately before the final design completion-line guidance.

#### Scenario: Helper instruction appears before completion-line guidance
- **WHEN** `ai/scripts/ai_design.sh` emits the design prompt contract
- **THEN** it includes a concise instruction to run `ai/scripts/helpers/check_design_readiness.sh` before the `When design phase is fully complete...` completion-line instruction

#### Scenario: Ready design may emit the completion line
- **WHEN** the model runs the helper during design completion and the helper exits `0`
- **THEN** the design phase may emit the standard completion line

#### Scenario: Unready design must not emit the completion line
- **WHEN** the model runs the helper during design completion and the helper exits non-zero
- **THEN** the design phase does not emit the standard completion line yet

### Requirement: Design readiness failure MUST use the two-path user decision contract
When design readiness validation fails, the design phase MUST ask the user to choose between continuing design iteration with a re-check or forcing the design phase done and proceeding.

#### Scenario: Design offers exactly two readiness options
- **WHEN** design readiness validation fails during design completion
- **THEN** the design response presents exactly two options: continue iterating on design and re-check, or force the design phase done and proceed

#### Scenario: Continue-and-recheck keeps readiness unresolved
- **WHEN** the user chooses to continue iterating on design after a readiness failure
- **THEN** the design phase remains open until the helper passes on re-check

#### Scenario: Force-done allows planning to proceed
- **WHEN** the user chooses to force the design phase done after a readiness failure
- **THEN** the design phase may finish and planning may proceed without requiring the readiness helper to pass for that run
