## ADDED Requirements

### Requirement: Pre-review explanation summary
Before entering Section 5 user review, the system MUST provide a brief human-readable explanation of implemented changes for the current step.

#### Scenario: Explanation is emitted at review handoff
- **WHEN** the implementation phase reaches the user-review entry point after completing required verification gates
- **THEN** the assistant provides a concise explanation summary before requesting user review feedback

### Requirement: Three-part reviewer guidance
The pre-review explanation MUST include exactly these three guidance elements in human-friendly language: what was changed and how, how to start code review, and what to check first.

#### Scenario: Required guidance elements are present
- **WHEN** the assistant emits the pre-review explanation
- **THEN** the explanation includes all three required guidance elements in a clearly separable structure

### Requirement: Concise output contract
The pre-review explanation MUST be brief and focused, without replacing detailed technical artifacts or introducing unrelated content.

#### Scenario: Explanation remains concise and scoped
- **WHEN** the assistant generates the pre-review explanation
- **THEN** the content stays short, references only current-step implementation scope, and defers deeper detail to existing artifacts and diffs

### Requirement: Process-source authority
Detailed explanation-mode rules MUST be maintained in `ai/AI_DEVELOPMENT_PROCESS.md`, while script prompts MUST keep only concise phase reminders.

#### Scenario: Rule location follows governance model
- **WHEN** explanation-mode behavior is updated
- **THEN** detailed policy updates are made in `ai/AI_DEVELOPMENT_PROCESS.md` and script prompts remain minimal
