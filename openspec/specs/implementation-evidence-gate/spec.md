## ADDED Requirements

### Requirement: Bullet completion requires explicit implementation proof
The system MUST evaluate each implementation bullet with an explicit proof check before changing bullet status from `[ ]` to `[x]`.

#### Scenario: Proven bullet may be marked complete
- **WHEN** the implementation flow evaluates a specific bullet and finds concrete code and test evidence mapped to that bullet
- **THEN** the bullet is classified as `PROVEN` and may be marked `[x]`

#### Scenario: Missing evidence keeps bullet incomplete
- **WHEN** the implementation flow cannot provide concrete proof for a specific bullet
- **THEN** the bullet is classified as `NOT_PROVEN` and remains `[ ]`

### Requirement: Evidence artifact is required before review handoff
For each implementation step, the system MUST generate an evidence artifact at `ai/implementation_evidence/step-<N>.md` before entering user review.

#### Scenario: Evidence file generated for implementation step
- **WHEN** implementation work for step `<N>` is reconciled before review
- **THEN** the system writes `ai/implementation_evidence/step-<N>.md`

#### Scenario: Missing evidence file blocks review transition
- **WHEN** the implementation flow attempts to transition to review without `ai/implementation_evidence/step-<N>.md`
- **THEN** the system blocks review transition and reports the missing evidence artifact

### Requirement: Evidence entries include traceable references
Each evidence entry for a bullet MUST include bullet identifier/text, status (`PROVEN` or `NOT_PROVEN`), code references, test references, and a completion decision.

#### Scenario: Proven entry includes code and test mapping
- **WHEN** a bullet is marked `PROVEN`
- **THEN** its evidence entry includes file path references, symbol/function/class references, test reference(s), and a short rationale linking bullet scope to implementation

#### Scenario: Not proven entry records hold decision
- **WHEN** a bullet is marked `NOT_PROVEN`
- **THEN** its evidence entry records missing proof and decision `keep [ ]`
