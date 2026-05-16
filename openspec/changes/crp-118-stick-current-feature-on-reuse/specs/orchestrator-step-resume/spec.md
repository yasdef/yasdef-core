## MODIFIED Requirements

### Requirement: Resume from first unfinished phase
The orchestrator SHALL support `--resume <step>` to evaluate the specified step against the canonical phase order and begin execution at the first phase that is not complete. Resume evaluation MUST treat design semantic readiness as design-phase handoff validation and MUST NOT block planning progression solely because the design artifact is missing `## Goal`, `## In Scope`, or `## Out of Scope`. Resume evaluation MUST treat planning semantic readiness as a planning/implementation handoff check owned by the phases and MUST NOT block implementation progression solely because `ai/step_plans/step-<N>.md` is missing, `## Plan (ordered)` is missing, `## Functional Requirements (translated from design EARS)` is missing, or the `Plan and discuss the step` bullet is missing or unchecked. For ai_audit completion and resume routing, the orchestrator MUST treat review-artifact semantic validation as a boundary-owned helper concern and MUST NOT decide ai_audit completeness based on presence of `## Disposition (per issue)` or on Accepted/Rejected disposition counts. When `feature_sync.yaml` is present and passes reuse validation, resume MUST treat the stored feature as the authoritative active context; if the stored feature is blocked or exhausted, resume MUST fail fast with an explicit error and MUST NOT rediscover another feature.

#### Scenario: Resume starts at first unfinished phase
- **WHEN** the operator runs the orchestrator with `--resume <step>` for a valid step that has completed early phases and an unfinished later phase
- **THEN** the orchestrator starts from the first unfinished phase and executes that phase and all remaining phases in order

#### Scenario: Resume starts at planning when design sections are incomplete
- **WHEN** the design artifact exists for the target step but is missing one or more of `## Goal`, `## In Scope`, or `## Out of Scope` and planning is otherwise the first unfinished phase
- **THEN** resume starts at `planning` and does not mark the design phase invalid because of the missing sections

#### Scenario: Resume starts at implementation when planning readiness artifacts are incomplete
- **WHEN** planning artifact semantics for the target step are incomplete but implementation is otherwise the first unfinished phase
- **THEN** resume starts at `implementation` and does not mark planning invalid because of missing step-plan structure or planning-gate closure

#### Scenario: Resume reuses valid current feature without rediscovery
- **WHEN** `feature_sync.yaml` is present and passes reuse validation and the stored feature has a runnable step
- **THEN** resume proceeds with the stored feature and step without running global candidate discovery

#### Scenario: Resume fails fast when valid current feature is blocked
- **WHEN** `feature_sync.yaml` passes reuse validation but the stored feature's assigned step is blocked by an upstream step
- **THEN** resume exits non-zero with an error naming the current feature and the blocking step
- **THEN** resume does not discover or switch to a different feature

#### Scenario: Resume fails fast when valid current feature is exhausted
- **WHEN** `feature_sync.yaml` passes reuse validation but all assigned steps in the stored feature are complete
- **THEN** resume exits non-zero with an error stating the current feature is exhausted
- **THEN** resume does not discover or switch to a different feature

### Requirement: Resume evaluation SHALL not own implementation-readiness checklist enforcement
When evaluating the `implementation` to `user_review` boundary, orchestrator resume logic MUST NOT use ordered-plan checklist semantics or translated functional-requirement checklist semantics to invalidate implementation completion or block downstream phase selection.

#### Scenario: Resume does not block on ordered-plan checklist semantics
- **WHEN** resume evaluates a step whose ordered-plan section is missing, empty, or not fully checked
- **THEN** orchestrator does not block resume progression on that basis alone
- **THEN** ordered-plan readiness enforcement remains the responsibility of implementation and `user_review`

#### Scenario: Resume does not block on translated functional-requirement semantics
- **WHEN** resume evaluates a step whose translated functional requirements are missing, empty, or not fully checked
- **THEN** orchestrator does not block resume progression on that basis alone
- **THEN** translated functional-requirement readiness enforcement remains the responsibility of implementation and `user_review`

#### Scenario: Resume starts at user_review after completed implementation
- **WHEN** design, planning, and implementation phases are complete for the target step and `user_review` is incomplete
- **THEN** resume starts at `user_review` and does not re-run implementation

#### Scenario: Resume starts at ai_audit after completed user_review
- **WHEN** design, planning, implementation, and `user_review` phases are complete for the target step and `ai_audit` is incomplete
- **THEN** resume starts at `ai_audit` and does not re-run earlier phases

#### Scenario: Resume does not reopen ai_audit for missing disposition section
- **WHEN** the review artifact exists for the target step, ai_audit is otherwise the last completed phase artifact, and the artifact is missing `## Disposition (per issue)`
- **THEN** the orchestrator does not mark ai_audit invalid because of the missing disposition section
- **THEN** resume routing is determined by later phase completeness instead of reopening ai_audit for semantic validation

#### Scenario: Resume does not reopen ai_audit for insufficient disposition counts
- **WHEN** the review artifact exists for the target step and its Accepted/Rejected disposition count is lower than the counted issues in the severity sections
- **THEN** the orchestrator does not mark ai_audit invalid because of disposition-count semantics
- **THEN** resume routing is determined by later phase completeness instead of reopening ai_audit for semantic validation
