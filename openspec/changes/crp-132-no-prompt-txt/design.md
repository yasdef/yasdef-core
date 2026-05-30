## Context

The orchestrator builds a prompt string for each phase (design, planning, implementation, user_review), writes it to a `.txt` file under `.asdlc_worker/prompts/`, reads it back via `build_model_prompt_arg()`, and passes the content as a CLI argument to the model. The file is never read again after that call. The write-then-read roundtrip is pure overhead.

## Goals / Non-Goals

**Goals:**
- Remove the prompt file write/read cycle for all four phase runners
- Pass prompt content inline to the model CLI call
- Simplify orchestrator by removing prompt directory scaffolding and related helpers

**Non-Goals:**
- Changing how the model is invoked (CLI command, flags, model name)
- Changing what the prompt contains
- Removing any other audit artifacts (logs in `.asdlc_worker/logs/` are unaffected)

## Decisions

**Pass prompt as bash variable, not heredoc or file**

Build the prompt string into a local bash variable in each phase runner and pass it directly as the CLI argument. This is the minimal diff from the current code — the `printf` calls in `write_*_skill_prompt()` become assignments into a variable instead of writes to a file.

Alternative considered: keep files but make them optional. Rejected — the whole point is to remove the indirection entirely.

**Remove `build_model_prompt_arg()` entirely**

The function exists only to branch on whether to `cat` the file (codex) or emit `run <path>` (other models). With inline prompts, codex always gets the string directly. Non-codex model support can be handled inline in each phase runner or dropped if only codex is used.

**Remove prompt directory scaffolding**

`resolve_prompt_output_path()`, the `ensure_dir_writable` calls for prompt dirs, and the `ASDLC_PROMPTS_DIR/*/` subdirectory initialization in `init_dirs()` all become dead code and should be removed.

## Risks / Trade-offs

- **Loss of prompt audit trail** → Accepted trade-off per product decision; logs still capture full model output.
- **Tests asserting prompt file content** → Tests like `test_user_review_writes_compact_skill_prompt` will need to be removed or rewritten to assert on model invocation args instead.

## Migration Plan

1. For each phase runner, replace `write_*_skill_prompt` + `build_model_prompt_arg` with a local variable holding the prompt string.
2. Remove the four `write_*_skill_prompt()` functions.
3. Remove `build_model_prompt_arg()` and `resolve_prompt_output_path()`.
4. Remove prompt dir initialization from `init_dirs()` and `ensure_dir_writable` calls.
5. Update or remove tests that assert on prompt file existence/content.
