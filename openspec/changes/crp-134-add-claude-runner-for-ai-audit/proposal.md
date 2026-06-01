## Why

The orchestrator currently hardcodes the Codex invocation shape (`$MODEL_CMD -m $MODEL_MODEL <args...> "$prompt"`) in all five phase functions, so swapping in a different model runner means editing five places and reasoning about Codex-specific flags (`--config model_reasoning_effort='high'`, positional prompt) that Claude Code does not share. CRP-133 just installed a Claude-side `yasdef-worker-ai-audit` skill at `.claude/skills/yasdef-worker-ai-audit/`, but the orchestrator cannot actually dispatch the ai_audit phase to `claude -p` yet — this change closes that gap by letting `models.md` route a phase to either runner.

## What Changes

- Extend `ai/scripts/orchestrator.sh` to accept `claude` as a value in the `cmd` column of `ai/setup/models.md` alongside `codex`. The `models.md` format itself is unchanged.
- Introduce one shared bash helper `build_phase_cmd "$prompt"` that produces the model-invocation argv array, dispatching on `$MODEL_CMD` to `build_codex_cmd` or `build_claude_cmd`. Replace the five inlined `cmd=()` blocks in `run_design_phase`, `run_planning_phase`, `run_implementation_phase`, `run_user_review_phase`, and `run_ai_audit_phase` with calls to this helper.
- `build_codex_cmd` reproduces the current behavior byte-for-byte: `codex -m <model> <MODEL_ARGS...> "<prompt>"`.
- `build_claude_cmd` applies four hardcoded transforms: swap `-m <model>` → `--model <model>`, add `--permission-mode acceptEdits`, drop all `MODEL_ARGS` entirely (hardcode-and-ignore-extras), deliver the prompt via `-p "<prompt>"` instead of positional.
- Allow `ai/setup/models.md` to carry rows of the shape `ai_audit | claude | claude-opus-4-7 |  |`; document the two-runner choice in the header comment.
- Add a focused test file `tests/ai_scripts/model_runner_tests.sh` asserting that `build_codex_cmd` and `build_claude_cmd` produce the expected argv given representative inputs.
- The orchestrator keeps building today's inline 7-input prompt (`run_ai_audit_phase`, orchestrator.sh:2110-2122); Claude picks up the skill via the `yasdef-worker-ai-audit` name. The `/yasdef:audit` slash command is **not** used for orchestrator-triggered runs.
- No changes to Codex skills, Claude skills, `init_asdlc_worker.sh`, `post_review.sh`, or any of the per-phase prompts.

## Capabilities

### New Capabilities

- `orchestrator-model-runner-dispatch`: Defines how the orchestrator selects a model-runner CLI (codex or claude) per phase from `models.md` and assembles a runner-correct argv that delivers the same inline prompt body. Owns the two-runner contract: codex behavior is preserved verbatim; Claude's flags are hardcoded by the orchestrator (not configurable from `models.md`).

### Modified Capabilities

_None — no existing spec governs orchestrator model-runner invocation today._

## Impact

- `ai/scripts/orchestrator.sh`: adds `build_phase_cmd`, `build_codex_cmd`, `build_claude_cmd` helpers; replaces five inlined `cmd=()` blocks (one per phase function) with calls to the helper.
- `ai/setup/models.md`: header-comment doc update describing the two-runner choice and which flags Claude rows can/cannot carry. Operators can now write `ai_audit | claude | claude-opus-4-7 |  |`.
- `tests/ai_scripts/model_runner_tests.sh`: new file covering the helper's codex and claude branches.
- `ai/codex/skills/**`, `ai/claude/skills/**`, `ai/scripts/init_asdlc_worker.sh`, `ai/scripts/post_review.sh`: unchanged.
- Out of scope: Claude support for design / planning / implementation / user_review phases (their Claude skills are not installed yet — each is a future per-phase CRP); new model-config knobs (`--max-turns`, `--allowed-tools`, `--thinking-tokens`); any `models.md` parser change; interactive runner-picker at orchestrator startup; orchestrator-to-Python migration (tracked separately in `design_docs/orchestrator_to_python.md`).
