## ADDED Requirements

### Requirement: Design artifact SHALL include selected target bullets and selected EARS requirement blocks
Design artifacts SHALL carry step-specific target bullets and concrete requirement excerpts selected from EARS as the source bridge into planning.

#### Scenario: Design captures target bullets for the step
- **WHEN** design artifact is created for a step
- **THEN** it includes the relevant target bullets that define intended outcome scope

#### Scenario: Design captures selected EARS blocks
- **WHEN** design artifact is created for a step
- **THEN** it includes specific selected EARS requirement blocks needed for implementation planning

### Requirement: Step plan SHALL use ordered bullets plus translated functional requirements
Step plans SHALL represent execution with `## Plan (ordered)` and translated implementation-specific functional requirements derived from design context.

#### Scenario: Step plan contains translated functional requirements derived from design
- **WHEN** planning finalizes a step plan
- **THEN** it includes a translated functional requirements section sourced from design-selected EARS context

#### Scenario: Step plan excludes target-bullet and requirement-tag execution sections
- **WHEN** planning emits step-plan structure
- **THEN** it does not require `## Target Bullets` or requirement-tag execution coupling in the plan artifact

### Requirement: Planning SHALL translate selected EARS blocks into functional requirements with deterministic traceability
Planning SHALL convert design-selected EARS blocks into step-plan functional requirements using deterministic mapping and required traceability fields.

#### Scenario: Every selected EARS block is covered
- **WHEN** planning processes selected EARS blocks from design
- **THEN** every selected EARS block maps to one or more translated functional requirements

#### Scenario: Each translated functional requirement has one source EARS block
- **WHEN** a translated functional requirement is emitted in the step plan
- **THEN** it references exactly one source EARS block ID and a design-artifact trace reference

#### Scenario: Translated statements are implementation-specific and testable
- **WHEN** planning emits a translated functional requirement statement
- **THEN** it uses `SHALL` language and includes implementation scope, behavior, and observable outcome

### Requirement: Step plan SHALL use a canonical template for each translated functional requirement
Each translated functional requirement in the step plan SHALL follow one canonical field template for execution and verification.

#### Scenario: Canonical requirement entry includes required fields
- **WHEN** a translated functional requirement is present in step plan
- **THEN** it includes `FR-ID`, `Source EARS Block`, `Requirement`, `Plan Links`, `Verification`, and `Status`

#### Scenario: Plan links connect requirement to ordered execution bullets
- **WHEN** planning finalizes a translated functional requirement
- **THEN** `Plan Links` references one or more bullets from `## Plan (ordered)` that implement it

### Requirement: Implementation and user_review prompts SHALL consume translated functional requirements from step plan
Implementation and user_review prompt construction SHALL include translated functional requirements from the step plan together with ordered bullets.

#### Scenario: Implementation prompt includes ordered bullets and translated functional requirements
- **WHEN** implementation prompt is generated for a step
- **THEN** it includes `## Plan (ordered)` content and plan-level translated functional requirements as execution guidance

#### Scenario: user_review prompt uses same execution contract
- **WHEN** user_review prompt is generated for a step
- **THEN** it evaluates completion and review context against ordered bullets and plan-level translated functional requirements

### Requirement: Verification gate SHALL require completion of all translated functional requirements before Section 5
Section `### 4) Verification gates (required before Section 5)` SHALL block transition to Section 5 until all translated functional requirements are complete and verified.

#### Scenario: Section 4 blocks when translated functional requirements are incomplete
- **WHEN** Section 4 verification runs and any translated functional requirement status is not `done`
- **THEN** verification fails and workflow returns to implementation completion actions

#### Scenario: Section 4 passes only with verification evidence for all translated functional requirements
- **WHEN** Section 4 verification runs and all translated functional requirements are `done`
- **THEN** each requirement has recorded verification evidence and Section 5 may proceed

### Requirement: Contract enforcement tests SHALL detect regressions
Script tests SHALL fail when old contract sections are reintroduced or when mid-phase prompts bypass plan-level translated functional requirements.

#### Scenario: Reintroduced target-bullet section fails tests
- **WHEN** step-plan generation or fixtures include deprecated `## Target Bullets` execution contract
- **THEN** prompt/validation tests fail with explicit contract regression signal

#### Scenario: Missing translated functional requirements in mid-phase prompt fails tests
- **WHEN** implementation or user_review prompt omits plan-level translated functional requirements
- **THEN** relevant script tests fail and indicate missing execution-contract context

#### Scenario: Missing canonical template fields fails tests
- **WHEN** generated step plans omit required translated functional requirement fields
- **THEN** validation tests fail with a missing-template-fields contract error

#### Scenario: Missing Section 4 requirement-completion check fails tests
- **WHEN** verification-gate instructions do not require all translated functional requirements to be done before Section 5
- **THEN** process-contract tests fail with a gate-regression signal

### Requirement: Design MUST run a missing-discussion-points ambiguity scan before planning handoff
Before design is considered handoff-ready, the design phase MUST run a structured ambiguity scan focused on unresolved discussion points that can affect planning scope, sequencing, risk handling, or decision closure.

#### Scenario: Design handoff includes ambiguity-scan outcomes
- **WHEN** design finalizes a step artifact for planning handoff
- **THEN** the artifact contains outcomes of a missing-discussion-points scan for planning-relevant unresolved items

#### Scenario: No material ambiguity is explicitly stated
- **WHEN** design ambiguity scan finds no planning-relevant unresolved items
- **THEN** design handoff explicitly states that no missing discussion points require planning clarification

### Requirement: Design MUST normalize unresolved planning inputs into a single decision-ready block
Design-discovered unresolved items that require planning discussion MUST be normalized into `## Things to Decide (for final planning discussion)` using concrete, mutually exclusive options suitable for the existing two-option planning decision prompt model.

#### Scenario: Design emits canonical handoff section for unresolved items
- **WHEN** design identifies one or more unresolved planning-relevant discussion points
- **THEN** each item is placed under `## Things to Decide (for final planning discussion)` in decision-ready format

#### Scenario: Normalized items are prompt-ready without planner restructuring
- **WHEN** planning consumes the design `## Things to Decide (for final planning discussion)` block
- **THEN** planning can present the required user-facing clarification prompts without inventing new decision structure
