## ADDED Requirements

### Requirement: Step plan MUST declare Applicable UR shortlist
Planning artifacts MUST include a `## Applicable UR Shortlist` section in every `ai/step_plans/step-<N>.md` before planning can be considered complete.

#### Scenario: Missing shortlist section blocks planning gate
- **WHEN** planning validation runs for a step plan that does not contain `## Applicable UR Shortlist`
- **THEN** planning fails with a clear error that the section is required

### Requirement: Explicit none format MUST be accepted
The shortlist section MUST accept explicit no-rule selection only as the exact bullet `- None.`.

#### Scenario: Canonical none marker passes validation
- **WHEN** the shortlist section contains exactly `- None.` and no UR IDs
- **THEN** planning validation passes the shortlist content gate

#### Scenario: Non-canonical none marker is rejected
- **WHEN** the shortlist section uses free-text none variants
- **THEN** planning validation fails and instructs the planner to use exact `- None.`

### Requirement: UR shortlist entries MUST be UR IDs
When shortlist rules apply, each shortlist item MUST include a `UR-xxxx` ID (optional short rationale allowed) and MUST NOT include non-ID bullets.

#### Scenario: Curated UR ID list passes validation
- **WHEN** shortlist bullets are formatted as `- UR-xxxx` with optional rationale text
- **THEN** planning validation accepts the shortlist

#### Scenario: Non-ID shortlist item fails validation
- **WHEN** any shortlist bullet does not include a valid `UR-xxxx` ID and is not `- None.`
- **THEN** planning validation fails with a message requiring UR IDs or `- None.`

### Requirement: UR shortlist size cap MUST be enforced
Planning validation MUST enforce a maximum shortlist size of 8 UR IDs per step plan.

#### Scenario: Shortlist above cap fails with prioritization guidance
- **WHEN** the shortlist contains more than 8 UR IDs
- **THEN** planning validation fails with a message to prioritize and reduce shortlist size to 8 or fewer IDs

#### Scenario: Shortlist at or under cap passes size gate
- **WHEN** the shortlist contains between 1 and 8 UR IDs
- **THEN** planning validation passes the size gate

### Requirement: ai_plan MUST fail before prompt generation on invalid shortlist structure
`ai/scripts/ai_plan.sh` MUST perform shortlist gate checks before emitting planning prompt output and MUST exit non-zero on missing or invalid shortlist structure.

#### Scenario: Missing shortlist triggers pre-model fail-fast
- **WHEN** `ai/scripts/ai_plan.sh` is invoked for a step plan missing the shortlist section
- **THEN** script exits non-zero before planning prompt emission

#### Scenario: Invalid shortlist format triggers pre-model fail-fast
- **WHEN** `ai/scripts/ai_plan.sh` is invoked for a step plan with invalid shortlist content
- **THEN** script exits non-zero with actionable shortlist guidance before prompt emission

### Requirement: Implementation prompt MUST include step-plan UR shortlist context
`ai/scripts/ai_implementation.sh` MUST include `## Applicable UR Shortlist` context from the current step plan in emitted implementation prompt context.

#### Scenario: Step-plan shortlist appears in implementation prompt
- **WHEN** step plan contains a valid `## Applicable UR Shortlist`
- **THEN** implementation prompt includes that shortlist content for implementation-phase guidance

#### Scenario: Design shortlist does not override step-plan shortlist
- **WHEN** both step-plan shortlist and design shortlist exist and differ
- **THEN** implementation prompt uses step-plan shortlist as the primary source

#### Scenario: Missing step-plan shortlist falls back deterministically
- **WHEN** step plan shortlist is missing but design shortlist exists
- **THEN** implementation prompt uses design shortlist as fallback and indicates source deterministically

### Requirement: Planning examples MUST reflect canonical shortlist formats
Step plan template and golden example MUST show `## Applicable UR Shortlist` with canonical valid examples (`- None.` and UR-ID shortlist format).

#### Scenario: Template and golden example are aligned with validator
- **WHEN** planners use `ai/templates/step_plan_TEMPLATE.md` and `ai/golden_examples/step_plan_GOLDEN_EXAMPLE.md`
- **THEN** shortlist examples match accepted validation formats

### Requirement: Planning MUST treat design Things-to-Decide block as required clarification input
`ai/scripts/ai_plan.sh` guidance MUST instruct planning to treat design `## Things to Decide (for final planning discussion)` as required input for user-facing clarification and decision resolution.

#### Scenario: Planning prompt references design handoff block as required input
- **WHEN** planning prompt guidance is generated for a step with a design artifact
- **THEN** the guidance explicitly requires consuming `## Things to Decide (for final planning discussion)` from design before planning closure

#### Scenario: Script guidance remains minimal and process-aligned
- **WHEN** `ai/scripts/ai_plan.sh` is updated for this behavior
- **THEN** it only adds minimal critical wording and defers durable decision rules to `ai/AI_DEVELOPMENT_PROCESS.md`

### Requirement: Planning closure MUST enforce missing-discussion-points gate outcomes
Planning completion MUST fail if meaningful unresolved discussion points from design were skipped without explicit resolution or documented user deferral outcome in the step plan.

#### Scenario: Planning blocks when meaningful unresolved points are skipped
- **WHEN** design provides unresolved items for final planning discussion and planning ends without resolving or deferring one or more meaningful items
- **THEN** planning closure fails with guidance to complete discussion-point resolution

#### Scenario: Planning passes after full discussion-point closure
- **WHEN** all meaningful design-provided discussion points are resolved or explicitly deferred with recorded outcomes
- **THEN** planning closure passes the missing-discussion-points gate
