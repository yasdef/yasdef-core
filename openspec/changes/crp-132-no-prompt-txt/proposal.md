## Why

The orchestrator currently writes a prompt to a `.txt` file on disk, then immediately reads it back to pass to the model CLI. This write-then-read cycle exists solely for audit trail purposes, but the audit value is low and the indirection adds unnecessary complexity to the orchestrator code.

## What Changes

- Remove `write_*_skill_prompt()` functions for all four phases (design, planning, implementation, user_review)
- Remove `resolve_prompt_output_path()` and prompt directory scaffolding
- Remove `build_model_prompt_arg()` helper
- Pass prompt content directly as a CLI argument when invoking the model
- Remove `ensure_dir_writable` calls for prompt dirs

## Capabilities

### New Capabilities

<!-- None introduced -->

### Modified Capabilities

- `orchestrator-user-review-phase`: Orchestrator no longer writes a prompt file before invoking the user_review model; prompt is passed inline.

## Impact

- `ai/scripts/orchestrator.sh`: significant simplification — prompt write/read plumbing removed from all four phase runners
- `.asdlc_worker/prompts/` directory will no longer be populated at runtime
- Tests asserting on prompt file existence/content will need updating
