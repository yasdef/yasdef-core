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
- **THEN** `BUILD_PHASE_CMD` equals `(claude --model claude-opus-4-7 --permission-mode acceptEdits -p "<prompt>")` element-by-element

#### Scenario: cmd=claude with trailing args silently drops them
- **WHEN** `models.md` carries the row `ai_audit | claude | claude-opus-4-7 | --config | model_reasoning_effort='high'` and `build_phase_cmd "<prompt>"` is called for the `ai_audit` phase
- **THEN** `BUILD_PHASE_CMD` equals `(claude --model claude-opus-4-7 --permission-mode acceptEdits -p "<prompt>")` element-by-element
- **THEN** neither `--config` nor `model_reasoning_effort='high'` appear anywhere in `BUILD_PHASE_CMD`

#### Scenario: cmd is a non-claude value (codex-shape fallback)
- **WHEN** `models.md` carries the row `ai_audit | .asdlc_worker/scripts/fake_model.sh | mock-model |  |` and `build_phase_cmd "<prompt>"` is called for the `ai_audit` phase
- **THEN** `BUILD_PHASE_CMD` equals `(.asdlc_worker/scripts/fake_model.sh -m mock-model "<prompt>")` element-by-element
- **THEN** no `--model`, `--permission-mode`, or `-p` flag appears in `BUILD_PHASE_CMD`

#### Scenario: Phase functions no longer construct model argv inline
- **WHEN** the orchestrator runs any of the five phases (design, planning, implementation, user_review, ai_audit)
- **THEN** the phase function calls `build_phase_cmd "<prompt>"` exactly once
- **THEN** the phase function does NOT contain an inlined `cmd=("$MODEL_CMD" -m "$MODEL_MODEL" ...)` array literal

### Requirement: Claude runner invocation has fixed shape and ignores models.md extras

When `cmd` is `claude`, the orchestrator SHALL apply exactly these four transforms relative to the Codex shape:

1. Replace `-m <model>` with `--model <model>`.
2. Add `--permission-mode acceptEdits` after the model flag.
3. Drop every entry from `MODEL_ARGS` (the parsed extras column from `models.md`).
4. Deliver the prompt via `-p "<prompt>"` instead of as a positional argument.

The orchestrator SHALL NOT read any other Claude-specific configuration from `models.md`. New Claude flags (e.g., `--max-turns`, `--allowed-tools`, `--output-format`) SHALL require a code change to `build_claude_cmd`, not a `models.md` change.

#### Scenario: Claude argv contains the four hardcoded transforms
- **WHEN** any phase with `cmd=claude` is dispatched
- **THEN** the resulting argv contains `--model <model-id>` (not `-m <model-id>`)
- **THEN** the resulting argv contains `--permission-mode acceptEdits`
- **THEN** the prompt appears as the value following a `-p` flag, not as a trailing positional argument
- **THEN** no element from `MODEL_ARGS` appears in the argv

#### Scenario: Same inline prompt body is used for both runners
- **WHEN** the same phase function builds its prompt string and dispatches via `build_phase_cmd`
- **THEN** the prompt string handed to `build_phase_cmd` is identical whether `cmd` is `codex` or `claude`
- **THEN** the orchestrator does NOT alter the prompt body based on runner choice

### Requirement: models.md documents the two-runner choice

The header comment of `ai/setup/models.md` SHALL document that the `cmd` column accepts `codex` and `claude` as values, and SHALL state that `claude` rows ignore the trailing extras columns.

#### Scenario: Header comment lists both runners
- **WHEN** an operator reads `ai/setup/models.md`
- **THEN** the header comment names both `codex` and `claude` as accepted `cmd` values
- **THEN** the header comment states that for `claude` rows, the trailing extras (`--config ...` etc.) are ignored
