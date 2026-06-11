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

#### Scenario: Implementation skill guidance remains concise
- **WHEN** `.codex/skills/yasdef-worker-implementation/SKILL.md` defines implementation guidance
- **THEN** it references process gates without duplicating long process prose from `ai/AI_DEVELOPMENT_PROCESS.md`

### Requirement: Proof gate still controls checkbox completion
Implementation bullets MUST only be marked `[x]` when proof criteria are satisfied according to process rules; otherwise they remain `[ ]`.

#### Scenario: Proven work can be checked
- **WHEN** an implementation bullet has sufficient proof per process rules
- **THEN** the bullet may be marked `[x]`

#### Scenario: Unproven work remains unchecked
- **WHEN** a bullet lacks sufficient proof per process rules
- **THEN** the bullet remains `[ ]`

### Requirement: Implementation completion SHALL be gated by the implementation skill readiness script
The implementation phase MUST require the implementation model to run `.codex/skills/yasdef-worker-implementation/scripts/check_implementation_readiness.py` before it emits its completion line, and MUST treat any non-zero exit as proof that implementation is not ready to leave the phase.

#### Scenario: Completion line is emitted only after readiness passes
- **WHEN** the implementation model finishes step work and runs the implementation skill readiness script
- **THEN** it emits the implementation completion line only if the helper exits successfully

#### Scenario: Failed readiness keeps the phase open
- **WHEN** the implementation model runs the implementation skill readiness script and it exits non-zero
- **THEN** implementation does not emit its completion line
- **THEN** implementation follows the remediation workflow defined in `ai/AI_DEVELOPMENT_PROCESS.md` for the Implementation Readiness Gate

### Requirement: Implementation readiness script SHALL use step-plan completion state as the source of truth
The implementation skill readiness script MUST evaluate `ai/step_plans/step-<N>.md` `## Plan (ordered)` checklist state and translated functional-requirement checklist state as the source of truth, and MUST communicate readiness success or failure through exit status.

#### Scenario: Helper fails on incomplete ordered plan state
- **WHEN** `## Plan (ordered)` is missing, empty, or contains unchecked items
- **THEN** the helper exits non-zero and reports that implementation readiness has not been satisfied

#### Scenario: Helper fails on incomplete translated functional requirements
- **WHEN** translated functional requirements are missing, empty, or contain unchecked items
- **THEN** the helper exits non-zero and reports that implementation readiness has not been satisfied

### Requirement: Implementation readiness recovery SHALL be documented centrally
The authoritative recovery steps for implementation-readiness script failure MUST live in the implementation skill and the Implementation Readiness Gate section in `ai/AI_DEVELOPMENT_PROCESS.md`, while orchestrator prompt text remains variable-only.

#### Scenario: Process documentation contains the detailed readiness workflow
- **WHEN** contributors consult the implementation completion contract
- **THEN** `ai/AI_DEVELOPMENT_PROCESS.md` contains a dedicated Implementation Readiness Gate section describing how to correct readiness-helper failures before retrying completion

#### Scenario: Orchestrator prompt guidance stays concise while deferring details
- **WHEN** the orchestrator prepares implementation guidance for the model
- **THEN** it names `yasdef-worker-implementation` and passes variables only instead of duplicating the full workflow inline
