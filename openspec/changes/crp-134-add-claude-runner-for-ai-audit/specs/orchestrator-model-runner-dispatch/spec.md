## ADDED Requirements

### Requirement: Orchestrator dispatches model invocation by cmd column in models.md

The orchestrator (`ai/scripts/orchestrator.sh`) SHALL select the model-runner argv shape for each phase by reading the `cmd` column of the matching row in `ai/setup/models.md`. When `cmd` equals `claude`, the orchestrator SHALL build a Claude Code argv (see "Claude runner invocation has fixed shape" below). For any other `cmd` value, the orchestrator SHALL build today's Codex-shape argv: `<cmd> -m <model> <MODEL_ARGS...> "<prompt>"`. This permissive default preserves the pre-CRP semantics in which the `cmd` column was always treated as the executable path/name to invoke, so existing test fixtures that substitute `echo` or a local script for the model CLI continue to work unchanged.

The orchestrator SHALL provide a shared helper `build_phase_cmd "<prompt>"` that assembles the argv array for the selected runner and writes it to a global `BUILD_PHASE_CMD` variable. The five phase functions (`run_design_phase`, `run_planning_phase`, `run_implementation_phase`, `run_user_review_phase`, `run_ai_audit_phase`) SHALL invoke `build_phase_cmd` rather than constructing the model command inline.

#### Scenario: cmd=codex builds today's invocation shape
- **WHEN** `models.md` carries the row `ai_audit | codex | gpt-5.5 | --config | model_reasoning_effort='high'` and `build_phase_cmd "<prompt>"` is called for the `ai_audit` phase
- **THEN** `BUILD_PHASE_CMD` equals `(codex -m gpt-5.5 --config model_reasoning_effort='high' "<prompt>")` element-by-element
- **THEN** no other flags are added

#### Scenario: cmd=claude builds the Claude-Code-correct invocation
- **WHEN** `models.md` carries the row `ai_audit | claude | claude-opus-4-7 |  |` and `build_phase_cmd "<prompt>"` is called for the `ai_audit` phase
- **THEN** `BUILD_PHASE_CMD` equals `(claude --model claude-opus-4-7 "<prompt>")` element-by-element

#### Scenario: cmd=claude passes models.md extras through verbatim
- **WHEN** `models.md` carries the row `ai_audit | claude | claude-opus-4-7 | --allowed-tools | Bash,Read,Write,Edit,Grep,Glob` and `build_phase_cmd "<prompt>"` is called for the `ai_audit` phase
- **THEN** `BUILD_PHASE_CMD` equals `(claude --model claude-opus-4-7 --allowed-tools Bash,Read,Write,Edit,Grep,Glob "<prompt>")` element-by-element

#### Scenario: cmd is a non-claude value (codex-shape fallback)
- **WHEN** `models.md` carries the row `ai_audit | .asdlc_worker/scripts/fake_model.sh | mock-model |  |` and `build_phase_cmd "<prompt>"` is called for the `ai_audit` phase
- **THEN** `BUILD_PHASE_CMD` equals `(.asdlc_worker/scripts/fake_model.sh -m mock-model "<prompt>")` element-by-element
- **THEN** no `--model` or `-p` flag appears in `BUILD_PHASE_CMD`

#### Scenario: Phase functions no longer construct model argv inline
- **WHEN** the orchestrator runs any of the five phases (design, planning, implementation, user_review, ai_audit)
- **THEN** the phase function calls `build_phase_cmd "<prompt>"` exactly once
- **THEN** the phase function does NOT contain an inlined `cmd=("$MODEL_CMD" -m "$MODEL_MODEL" ...)` array literal

### Requirement: Claude runner invocation differs from Codex only in the model flag

When `cmd` is `claude`, the orchestrator SHALL apply exactly one structural transform relative to the Codex shape: replace `-m <model>` with `--model <model>`. The prompt SHALL be delivered as a trailing positional argument (the same shape as `claude "explain this"` from a terminal), and all entries from `MODEL_ARGS` SHALL pass through verbatim between `--model <model>` and the prompt.

The orchestrator's `run_with_output_log` SHALL preserve a TTY for both `codex` and `claude` invocations (via `script -q <log>`) when stdout is a terminal, so claude opens its interactive UI for tool approvals while the run is still captured to the audit log.

#### Scenario: Claude argv differs from Codex only in the model-flag spelling
- **WHEN** any phase with `cmd=claude` is dispatched
- **THEN** the resulting argv contains `--model <model-id>` (not `-m <model-id>`)
- **THEN** the prompt appears as the trailing positional argument
- **THEN** every element from `MODEL_ARGS` appears in the argv between `--model <model-id>` and the prompt, in the original order
- **THEN** the resulting argv does NOT contain `-p`

#### Scenario: Claude runs interactively under run_with_output_log
- **WHEN** any phase with `cmd=claude` is launched via `run_with_output_log` and stdout is a TTY
- **THEN** the launch wraps the claude argv in `script -q <log-path>` so claude inherits a pseudo-TTY
- **THEN** the run is also captured to `<log-path>` for the audit trail

#### Scenario: Same inline prompt body is used for both runners
- **WHEN** the same phase function builds its prompt string and dispatches via `build_phase_cmd`
- **THEN** the prompt string handed to `build_phase_cmd` is identical whether `cmd` is `codex` or `claude`
- **THEN** the orchestrator does NOT alter the prompt body based on runner choice

### Requirement: models.md documents the two-runner choice

The header comment of `ai/setup/models.md` SHALL document that the `cmd` column accepts `codex` and `claude` as values, name the structural difference (`-m` vs `--model`, both positional prompt), and note that extras pass through verbatim for both runners.

#### Scenario: Header comment lists both runners
- **WHEN** an operator reads `ai/setup/models.md`
- **THEN** the header comment names both `codex` and `claude` as accepted `cmd` values
- **THEN** the header comment shows the resulting argv shape for each runner
