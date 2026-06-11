## MODIFIED Requirements

### Requirement: Orchestrator routes assigned worker steps through lifecycle phases
The orchestrator MUST preserve existing assigned-step selection and phase ordering, and for the design phase it MUST invoke the configured model with a prompt that calls the `yasdef-worker-design` skill instead of running the legacy design prompt generator.

#### Scenario: Design phase prompt calls design skill
- **WHEN** the orchestrator runs the design phase for a selected step
- **THEN** it writes a compact design prompt that instructs the model to use `yasdef-worker-design`
- **AND** the prompt includes the selected step, feature id, design output path, runtime plan path, and runtime EARS path

#### Scenario: Design phase does not require legacy script
- **WHEN** the orchestrator validates runtime prerequisites before executing phases
- **THEN** it does not require `.asdlc_worker/scripts/ai_design.sh`

#### Scenario: Later phase behavior remains unchanged
- **WHEN** planning, implementation, user review, ai audit, or post review phases run
- **THEN** their existing script invocation and readiness behavior remains unchanged
