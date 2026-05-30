## MODIFIED Requirements

### Requirement: Orchestrator supports a distinct User Review phase
The orchestrator MUST treat `user_review` as a first-class phase between implementation and post-step AI audit execution flow. The orchestrator MUST pass the skill invocation prompt inline to the model CLI without writing an intermediate prompt file to disk.

#### Scenario: Default phase order includes user_review
- **WHEN** orchestrator runs its default ordered phase execution
- **THEN** phase order includes `user_review` after `implementation` and before `ai_audit`

#### Scenario: Explicit user_review phase execution is supported
- **WHEN** the operator runs orchestrator with `--phase user_review`
- **THEN** orchestrator executes the User Review phase pipeline for the resolved step

#### Scenario: No prompt file is written during user_review execution
- **WHEN** orchestrator invokes the user_review phase
- **THEN** no prompt `.txt` file is written under `.asdlc_worker/prompts/`
- **THEN** the skill invocation prompt is passed directly as a CLI argument to the model
