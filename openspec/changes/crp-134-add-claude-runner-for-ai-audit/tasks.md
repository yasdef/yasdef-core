## 1. Extract shared command builder (no behavior change)

- [x] 1.1 In `ai/scripts/orchestrator.sh`, add a global `BUILD_PHASE_CMD=()` declaration alongside `MODEL_CMD` / `MODEL_MODEL` / `MODEL_ARGS`.
- [x] 1.2 Add `build_codex_cmd "$prompt"` function right after `load_model_config` (line ~511). Implementation: assigns `BUILD_PHASE_CMD=("$MODEL_CMD" -m "$MODEL_MODEL"); BUILD_PHASE_CMD+=("${MODEL_ARGS[@]}"); BUILD_PHASE_CMD+=("$prompt")`. Reproduces today's inlined block byte-for-byte.
- [x] 1.3 Add `build_phase_cmd "$prompt"` dispatcher function right after `build_codex_cmd`. Implementation: `case "$MODEL_CMD"` with a `claude` arm calling `build_claude_cmd "$prompt"` and a default arm calling `build_codex_cmd "$prompt"`. Any non-`claude` value uses the codex shape — this preserves the pre-CRP convention in which the `cmd` column was the executable path/name (existing tests substitute `echo` / fake scripts).
- [x] 1.4 In `run_design_phase` (around line 833), replace the inlined `cmd=("$MODEL_CMD" -m "$MODEL_MODEL")` / `MODEL_ARGS` append / prompt append block with `build_phase_cmd "$prompt_arg"` and use `${BUILD_PHASE_CMD[@]}` in the `run_with_output_log` call.
- [x] 1.5 Apply the same substitution in `run_planning_phase` (around line 718).
- [x] 1.6 Apply the same substitution in `run_implementation_phase` (around line 1960).
- [x] 1.7 Apply the same substitution in `run_user_review_phase` (around line 2049).
- [x] 1.8 Apply the same substitution in `run_ai_audit_phase` (around line 2136).
- [x] 1.9 Apply the same substitution to the dry-run command-array builders in each of the five phase functions (lines 689, 821, 1949, 2026, 2125), or factor them through `build_phase_cmd` as well — whichever keeps the dry-run output shape unchanged.
- [x] 1.10 Run all existing orchestrator-touching tests (`tests/ai_scripts/orchestrator_*.sh`); confirm pass with no behavior change.

## 2. Add Claude branch

- [x] 2.1 Add `build_claude_cmd "$prompt"` function below `build_codex_cmd`. Implementation: `BUILD_PHASE_CMD=("$MODEL_CMD" --model "$MODEL_MODEL" --permission-mode acceptEdits -p "$prompt")`. `MODEL_ARGS` is NOT read.
- [x] 2.2 Extend the `build_phase_cmd` dispatcher's `case` statement with a `claude` arm that calls `build_claude_cmd "$prompt"`.

## 3. Tests

- [x] 3.1 Create `tests/ai_scripts/model_runner_tests.sh` that sources `ai/scripts/orchestrator.sh` defensively (or extracts the helpers into a sourceable file if top-level side effects are a problem) and adds the standard `assert_*` helpers.
- [x] 3.2 Add `test_build_codex_cmd_with_extras`: sets `MODEL_CMD=codex MODEL_MODEL=gpt-5.5 MODEL_ARGS=(--config "model_reasoning_effort='high'")`, calls `build_phase_cmd "SAMPLE PROMPT"`, asserts `BUILD_PHASE_CMD` equals `(codex -m gpt-5.5 --config model_reasoning_effort='high' "SAMPLE PROMPT")` element-by-element.
- [x] 3.3 Add `test_build_claude_cmd_minimal`: sets `MODEL_CMD=claude MODEL_MODEL=claude-opus-4-7 MODEL_ARGS=()`, calls `build_phase_cmd "SAMPLE PROMPT"`, asserts `BUILD_PHASE_CMD` equals `(claude --model claude-opus-4-7 --permission-mode acceptEdits -p "SAMPLE PROMPT")` element-by-element.
- [x] 3.4 Add `test_build_claude_cmd_drops_extras`: sets `MODEL_CMD=claude MODEL_MODEL=claude-opus-4-7 MODEL_ARGS=(--config "model_reasoning_effort='high'")`, calls `build_phase_cmd "SAMPLE PROMPT"`, asserts `BUILD_PHASE_CMD` equals the same array as `test_build_claude_cmd_minimal` (extras are dropped).
- [x] 3.5 Add `test_build_phase_cmd_non_claude_falls_back_to_codex_shape`: sets `MODEL_CMD=.asdlc_worker/scripts/fake_model.sh MODEL_MODEL=mock-model MODEL_ARGS=()`, calls `build_phase_cmd "SAMPLE PROMPT"`, asserts `BUILD_PHASE_CMD` equals `(.asdlc_worker/scripts/fake_model.sh -m mock-model "SAMPLE PROMPT")` element-by-element.
- [x] 3.6 Add `test_phase_dry_run_for_claude`: runs the orchestrator's ai_audit phase in dry-run mode against a fixture `models.md` row of shape `ai_audit | claude | claude-opus-4-7 |  |`; asserts the printed command contains `--model claude-opus-4-7`, `--permission-mode acceptEdits`, and `-p`, and does NOT contain `-m ` or `--config`.

## 4. Documentation

- [x] 4.1 Update the header comment of `ai/setup/models.md` to document that `cmd` accepts `codex` and `claude`, and that `claude` rows ignore the trailing extras columns (the four hardcoded transforms apply). Example row in the comment: `# Example claude row: ai_audit | claude | claude-opus-4-7 |  |`.
- [x] 4.2 If `ai/AI_DEVELOPMENT_PROCESS.md` documents `models.md`, add a one-paragraph pointer to the runner-choice rule there as well.

## 5. Validate

- [x] 5.1 Run `bash tests/ai_scripts/model_runner_tests.sh` and confirm all five tests pass (codex with extras, codex no extras, claude minimal, claude drops extras, non-claude fallback).
- [x] 5.2 Run `bash tests/ai_scripts/init_asdlc_worker_tests.sh` and confirm pass (unchanged — proves the bootstrap install paths are unaffected).
- [x] 5.3 Run all `tests/ai_scripts/orchestrator_*.sh` tests and confirm pass (proves the refactor preserves Codex behavior). Note: `orchestrator_git_sync_tests.sh` was failing on `main` before this CRP (pre-existing, unrelated).
- [ ] 5.4 **DEFERRED to manual operator verification** — In a scratch worker repo with CRP-133's Claude skill installed, set `ai/setup/models.md` to `ai_audit | claude | claude-opus-4-7 |  |` and run the orchestrator's ai_audit phase end-to-end against a real step. Verify: (a) the launched process is `claude` with the four expected flags, (b) the Claude skill is picked up by name, (c) the closure gate passes, (d) the sentinel completion line is emitted. Requires real `claude` CLI and a real worker repo state; not runnable in CI/sandbox. Dry-run argv shape is already covered by `test_dry_run_ai_audit_with_claude_runner_emits_claude_argv` in `tests/ai_scripts/orchestrator_resume_tests.sh`.
- [ ] 5.5 **DEFERRED to manual operator verification** — Restore `ai/setup/models.md` to `ai_audit | codex | gpt-5.5 | --config | model_reasoning_effort='high'` and run the same ai_audit phase end-to-end; verify Codex behavior is unchanged. Same rationale as 5.4 — the refactor's no-regression property is covered by the existing orchestrator test suite (Section 5.3).
