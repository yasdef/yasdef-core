## MODIFIED Requirements

### Requirement: Resume from first unfinished phase
The orchestrator SHALL support `--resume <step>` to evaluate the specified step against the canonical phase order and begin execution at the first phase that is not complete. Resume evaluation MUST treat design semantic readiness as design-phase handoff validation and MUST NOT block planning progression solely because the design artifact is missing `## Goal`, `## In Scope`, or `## Out of Scope`. Resume evaluation MUST treat planning semantic readiness as a planning/implementation handoff check owned by the phases and MUST NOT block implementation progression solely because the step plan artifact is missing, `## Plan (ordered)` is missing, `## Functional Requirements (translated from design EARS)` is missing, or the `Plan and discuss the step` bullet is missing or unchecked. For ai_audit completion and resume routing, the orchestrator MUST treat review-artifact semantic validation as a boundary-owned helper concern and MUST NOT decide ai_audit completeness based on presence of `## Disposition (per issue)` or on Accepted/Rejected disposition counts. When a feature is selected during resume, phase completion checks SHALL use the feature-qualified artifact paths for that step and feature rather than step-only paths.

#### Scenario: Resume starts at first unfinished phase
- **WHEN** the operator runs the orchestrator with `--resume <step>` for a valid step that has completed early phases and an unfinished later phase
- **THEN** the orchestrator starts from the first unfinished phase and executes that phase and all remaining phases in order

#### Scenario: Resume starts at planning when design sections are incomplete
- **WHEN** the design artifact exists for the target step but is missing one or more of `## Goal`, `## In Scope`, or `## Out of Scope` and planning is otherwise the first unfinished phase
- **THEN** resume starts at `planning` and does not mark the design phase invalid because of the missing sections

#### Scenario: Resume starts at implementation when planning readiness artifacts are incomplete
- **WHEN** planning artifact semantics for the target step are incomplete but implementation is otherwise the first unfinished phase
- **THEN** resume starts at `implementation` and does not mark planning invalid because of missing step-plan structure or planning-gate closure

#### Scenario: Resume uses feature-qualified step plan to evaluate planning completion
- **WHEN** resume evaluates step N with selected feature `auth-system` and the step plan at `step_plans/step-N-auth-system.md` exists with implementation bullets checked
- **THEN** orchestrator uses that feature-qualified plan to determine planning completion and does not look for `step_plans/step-N.md`

#### Scenario: Resume uses feature-qualified design file to evaluate design completion
- **WHEN** resume evaluates step N with selected feature `auth-system` and `step_designs/step-N-auth-system-design.md` exists
- **THEN** orchestrator uses that feature-qualified design to determine design completion

#### Scenario: Resume uses feature-qualified review result to evaluate ai_audit completion
- **WHEN** resume evaluates step N with selected feature `auth-system` and `step_review_results/review_result-N-auth-system.md` exists
- **THEN** orchestrator marks ai_audit as complete based on that feature-qualified review result

#### Scenario: Standalone resume artifact lookup unchanged
- **WHEN** resume evaluates a step with no selected feature
- **THEN** orchestrator checks `step_plans/step-N.md`, `step_designs/step-N-design.md`, and `step_review_results/review_result-N.md` as before
