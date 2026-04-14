## ADDED Requirements

### Requirement: ai_audit accepts only canonical YASDEF TODO markers for plan handoff
The `ai_audit` phase MUST treat only canonical markers in the form `TODO YASDEF [BLK-<id>] [phase:user_review|ai_audit]: <reason>` as eligible inputs for follow-up step creation.

#### Scenario: Canonical marker is accepted
- **WHEN** a source line contains a marker matching the canonical `TODO YASDEF` format with valid blocker ID and phase tag
- **THEN** `ai_audit` includes that marker in the candidate list for step seeding

#### Scenario: Non-canonical marker is rejected
- **WHEN** a source line has a TODO-like marker missing `YASDEF`, blocker ID, or valid phase tag
- **THEN** `ai_audit` does not seed a follow-up step from that line and reports it as invalid marker format

### Requirement: ai_audit seeds implementation plan steps from valid markers
For each valid canonical marker, `ai_audit` MUST create a specific new unchecked follow-up step in `implementation_plan.md` that includes blocker ID and source reference.

#### Scenario: Valid marker creates follow-up step
- **WHEN** `ai_audit` processes a valid canonical marker that is not already represented in `implementation_plan.md`
- **THEN** it appends exactly one new unchecked follow-up step containing the blocker ID, concise reason, and source file reference

#### Scenario: Rerun remains idempotent
- **WHEN** `ai_audit` processes markers and an equivalent blocker-linked follow-up step already exists
- **THEN** it does not create a duplicate plan step for that blocker ID

### Requirement: Marker cleanup occurs only after successful step creation
`ai_audit` MUST remove consumed canonical markers from code only after corresponding follow-up step creation succeeds.

#### Scenario: Successful seeding removes marker
- **WHEN** a valid marker is converted into a new implementation-plan step successfully
- **THEN** `ai_audit` removes that marker from the source file in the same run

#### Scenario: Failed seeding preserves marker
- **WHEN** implementation-plan update fails before step creation completes
- **THEN** `ai_audit` does not remove corresponding canonical markers from source files

### Requirement: ai_audit emits deterministic TODO handoff summary
After marker processing, `ai_audit` MUST emit a concise quality-gate summary listing created follow-up steps and cleanup results.

#### Scenario: Summary lists created steps and removals
- **WHEN** `ai_audit` completes marker processing with one or more created steps
- **THEN** output includes created-step count, blocker IDs, and marker-removal count

#### Scenario: Summary reports no-op state
- **WHEN** no valid canonical markers are found
- **THEN** output explicitly states that no TODO-derived follow-up steps were created

### Requirement: Process rules define marker usage timing for review and audit
The process documentation MUST define that canonical `TODO YASDEF` markers are introduced only for concrete blockers discovered in `user_review` or `ai_audit`, and that each marker maps to blocker tracking.

#### Scenario: User-review marker policy is documented
- **WHEN** an operator checks process rules for `user_review`
- **THEN** documentation specifies when canonical markers may be added and required blocker ID linkage

#### Scenario: ai_audit policy is enforced
- **WHEN** `ai_audit` evaluates markers against documented policy
- **THEN** markers not satisfying policy are rejected from step seeding
