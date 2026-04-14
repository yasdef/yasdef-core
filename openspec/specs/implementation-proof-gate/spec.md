## ADDED Requirements

### Requirement: Implementation proof gate does not require separate evidence artifact file
The system MUST enforce proof-based completion decisions for implementation bullets without requiring a dedicated per-step evidence file under `ai/implementation_evidence/`.

#### Scenario: Implementation proceeds without evidence file dependency
- **WHEN** implementation and review orchestration run for a step
- **THEN** the flow does not require `ai/implementation_evidence/step-<N>.md` to exist

#### Scenario: Legacy evidence-file checks are removed
- **WHEN** scripts evaluate implementation/review preconditions
- **THEN** missing `ai/implementation_evidence/step-<N>.md` does not block phase progression

### Requirement: Detailed proof policy is anchored in process documentation
The authoritative details for proof-based bullet completion MUST live in `ai/AI_DEVELOPMENT_PROCESS.md`, while script prompt text remains concise.

#### Scenario: Process doc contains full proof rules
- **WHEN** implementation proof behavior is defined
- **THEN** detailed policy and decision criteria are specified in `ai/AI_DEVELOPMENT_PROCESS.md`

#### Scenario: Implementation script prompt remains concise
- **WHEN** `ai/scripts/ai_implementation.sh` emits implementation guidance
- **THEN** it contains at most a single short sentence referencing proof gating and defers details to `ai/AI_DEVELOPMENT_PROCESS.md`

### Requirement: Proof gate still controls checkbox completion
Implementation bullets MUST only be marked `[x]` when proof criteria are satisfied according to process rules; otherwise they remain `[ ]`.

#### Scenario: Proven work can be checked
- **WHEN** an implementation bullet has sufficient proof per process rules
- **THEN** the bullet may be marked `[x]`

#### Scenario: Unproven work remains unchecked
- **WHEN** a bullet lacks sufficient proof per process rules
- **THEN** the bullet remains `[ ]`

### Requirement: Implementation completion SHALL be gated by a shared readiness helper
The implementation phase MUST require the implementation model to run a shared readiness helper from `ai/scripts/helpers/` before it emits its completion line, and MUST treat any non-zero exit as proof that implementation is not ready to leave the phase.

#### Scenario: Completion line is emitted only after readiness passes
- **WHEN** the implementation model finishes step work and runs the shared readiness helper
- **THEN** it emits the implementation completion line only if the helper exits successfully

#### Scenario: Failed readiness keeps the phase open
- **WHEN** the implementation model runs the shared readiness helper and it exits non-zero
- **THEN** implementation does not emit its completion line
- **THEN** implementation follows the remediation workflow defined in `ai/AI_DEVELOPMENT_PROCESS.md` for the Implementation Readiness Gate

### Requirement: Shared readiness helper SHALL use step-plan completion state as the source of truth
The shared implementation-readiness helper MUST evaluate `ai/step_plans/step-<N>.md` `## Plan (ordered)` checklist state and translated functional-requirement checklist state as the source of truth, and MUST communicate readiness success or failure through exit status.

#### Scenario: Helper fails on incomplete ordered plan state
- **WHEN** `## Plan (ordered)` is missing, empty, or contains unchecked items
- **THEN** the helper exits non-zero and reports that implementation readiness has not been satisfied

#### Scenario: Helper fails on incomplete translated functional requirements
- **WHEN** translated functional requirements are missing, empty, or contain unchecked items
- **THEN** the helper exits non-zero and reports that implementation readiness has not been satisfied

### Requirement: Implementation readiness recovery SHALL be documented centrally
The authoritative recovery steps for implementation-readiness-helper failure MUST live in a dedicated Implementation Readiness Gate section in `ai/AI_DEVELOPMENT_PROCESS.md`, while implementation prompt/script text remains concise.

#### Scenario: Process documentation contains the detailed readiness workflow
- **WHEN** contributors consult the implementation completion contract
- **THEN** `ai/AI_DEVELOPMENT_PROCESS.md` contains a dedicated Implementation Readiness Gate section describing how to correct readiness-helper failures before retrying completion

#### Scenario: Prompt guidance stays concise while deferring details
- **WHEN** `ai/scripts/ai_implementation.sh` prepares implementation guidance for the model
- **THEN** it references the process document for detailed recovery rules instead of duplicating the full workflow inline
