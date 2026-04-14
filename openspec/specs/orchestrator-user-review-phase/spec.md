## ADDED Requirements

### Requirement: ai_audit phase naming is canonical for AI post-step audit
The orchestrator MUST use `ai_audit` as the canonical phase identifier for the AI post-step audit phase.

#### Scenario: Explicit ai_audit phase execution is supported
- **WHEN** the operator runs orchestrator with `--phase ai_audit`
- **THEN** orchestrator executes the AI audit phase pipeline for the resolved step

#### Scenario: Legacy review phase name is rejected
- **WHEN** the operator runs orchestrator with `--phase review`
- **THEN** orchestrator exits with a clear unsupported-phase error and requires `--phase ai_audit`

### Requirement: Interactive denial short-circuits downstream phase progression
In interactive runs, an explicit denial at a phase confirmation gate MUST terminate phase progression for the current run and MUST NOT prompt any subsequent phases in canonical order. This requirement explicitly includes denials at `planning` and `implementation`, with downstream suppression for `user_review`, `ai_audit`, and `post_review` as applicable.

#### Scenario: Planning denial prevents all later prompts
- **WHEN** orchestrator is running interactively and the operator denies progression at `planning`
- **THEN** orchestrator does not prompt for `implementation`, `user_review`, `ai_audit`, or `post_review`

#### Scenario: Implementation denial prevents remaining prompts
- **WHEN** orchestrator is running interactively and the operator denies progression at `implementation`
- **THEN** orchestrator does not prompt for `user_review`, `ai_audit`, or `post_review`

#### Scenario: User-review denial prevents audit and post-review prompts
- **WHEN** orchestrator is running interactively and the operator denies progression at `user_review`
- **THEN** orchestrator does not prompt for `ai_audit` or `post_review`

#### Scenario: AI-audit denial prevents post-review prompt
- **WHEN** orchestrator is running interactively and the operator denies progression at `ai_audit`
- **THEN** orchestrator does not prompt for `post_review`

### Requirement: Interactive denial emits deterministic terminal stop reason
When phase progression is denied in interactive mode, orchestrator MUST emit a single deterministic stop reason naming the denied phase.

#### Scenario: Stop reason is emitted once with denied phase
- **WHEN** an operator denies progression at an interactive phase gate
- **THEN** orchestrator emits exactly one terminal message in the form `Execution stopped: user denied phase progression at <phase>.`
- **THEN** orchestrator does not emit downstream continue prompts in the same run

## MODIFIED Requirements

### Requirement: Orchestrator supports a distinct User Review phase
The orchestrator MUST treat `user_review` as a first-class phase between implementation and post-step AI audit execution flow.

#### Scenario: Default phase order includes user_review
- **WHEN** orchestrator runs its default ordered phase execution
- **THEN** phase order includes `user_review` after `implementation` and before `ai_audit`

#### Scenario: Explicit user_review phase execution is supported
- **WHEN** the operator runs orchestrator with `--phase user_review`
- **THEN** orchestrator executes the User Review phase pipeline for the resolved step

### Requirement: Interactive confirmation includes User Review phase
In interactive runs, orchestrator MUST ask for confirmation before entering `user_review`, consistent with planning, implementation, and `ai_audit` confirmations.

#### Scenario: User Review confirmation prompt is shown
- **WHEN** orchestrator runs interactively and next phase is `user_review`
- **THEN** operator is prompted to confirm before phase execution continues

## ADDED Requirements

### Requirement: user_review SHALL run the shared implementation readiness helper before prompt generation
Before generating prompt content or starting model execution, `user_review` MUST invoke the same shared implementation-readiness helper used by implementation for ordered-plan and translated functional-requirement completion.

#### Scenario: user_review proceeds only after shared readiness succeeds
- **WHEN** `user_review` starts for a step and the shared readiness helper exits successfully
- **THEN** `user_review` may generate its prompt and start model execution

#### Scenario: user_review fails fast when shared readiness fails
- **WHEN** `user_review` starts for a step and the shared readiness helper exits non-zero
- **THEN** `user_review` exits before prompt generation and model start
- **THEN** it emits a clear message that implementation was not finished correctly and must be corrected before retrying `user_review`
