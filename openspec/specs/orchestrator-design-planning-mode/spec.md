## ADDED Requirements

### Requirement: Orchestrator supports an explicit rich design/planning mode flag
The orchestrator MUST support an opt-in flag `--feature-rich-design-planning` that enables richer design/planning behavior, and rich mode MUST default to disabled when the flag is omitted.

#### Scenario: Default mode remains unchanged
- **WHEN** the operator runs the orchestrator without `--feature-rich-design-planning`
- **THEN** design and planning behavior uses the existing default strict/minimal mode

#### Scenario: Rich mode is explicitly enabled
- **WHEN** the operator runs the orchestrator with `--feature-rich-design-planning`
- **THEN** the orchestrator enables rich design/planning behavior for that run

### Requirement: Rich mode affects only design and planning phases
When rich mode is enabled, the orchestrator MUST apply the mode only to design and planning phase prompt generation and MUST NOT change implementation, user_review, ai_audit, or post_review phase behavior.

#### Scenario: Rich mode is scoped to early phases only
- **WHEN** the orchestrator runs with `--feature-rich-design-planning`
- **THEN** only design and planning prompt inputs include rich-mode behavior

#### Scenario: Later phases are unchanged under rich mode
- **WHEN** implementation, user_review, ai_audit, or post_review phases run in a rich-mode session
- **THEN** their contracts and gating behavior remain identical to default mode

### Requirement: Rich mode design output captures bounded optional robustness opportunities
In rich mode, design guidance MUST require a bounded optional-robustness section that identifies additional hardening opportunities with explicit decision intent, while preserving required scope boundaries.

#### Scenario: Design prompt requests bounded optional hardening candidates
- **WHEN** rich mode is enabled and design prompt is generated
- **THEN** the prompt requests a concise, bounded list of optional hardening opportunities with accept/defer intent

#### Scenario: Design scope boundaries are preserved
- **WHEN** optional hardening opportunities are captured in rich mode
- **THEN** required in-scope commitments remain anchored to the original step scope unless explicitly accepted

### Requirement: Rich mode planning output enforces explicit optional-decision closure
In rich mode, planning guidance MUST require explicit accepted/deferred outcomes for optional hardening decisions before planning completion, using existing decision-prompt governance for unresolved blocking choices.

#### Scenario: Planning captures accepted and deferred optional items
- **WHEN** rich mode is enabled during planning
- **THEN** the resulting plan records explicit accepted/deferred outcomes for optional hardening decisions

#### Scenario: Blocking rich-mode decisions still require user confirmation
- **WHEN** a rich-mode planning choice is unresolved and blocking
- **THEN** the planner asks a two-option decision prompt and records the selected outcome before closure

### Requirement: Rich mode behavior is covered by prompt and orchestrator tests
The repository MUST include script-level tests that verify rich-mode behavior in design/planning and verify non-leakage to other phases.

#### Scenario: Rich-mode design/planning coverage exists
- **WHEN** script tests execute rich-mode prompt generation checks
- **THEN** tests confirm rich-mode contract appears in design and planning prompt outputs

#### Scenario: Rich-mode non-leakage coverage exists
- **WHEN** script tests execute rich-mode orchestration checks
- **THEN** tests confirm implementation, user_review, ai_audit, and post_review behavior is unchanged
