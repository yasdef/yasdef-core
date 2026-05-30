## 1. Remove prompt file helpers from orchestrator

- [ ] 1.1 Remove `write_design_skill_prompt()`, `write_planning_skill_prompt()`, `write_implementation_skill_prompt()`, and `write_user_review_skill_prompt()` functions
- [ ] 1.2 Remove `build_model_prompt_arg()` function
- [ ] 1.3 Remove `resolve_prompt_output_path()` function
- [ ] 1.4 Remove `ensure_dir_writable` calls for prompt dirs and prompt dir initialization in `init_dirs()`

## 2. Inline prompts in each phase runner

- [ ] 2.1 Replace `write_design_skill_prompt` + `build_model_prompt_arg` in `run_design_phase()` with a local variable holding the prompt string passed directly to the model CLI
- [ ] 2.2 Replace `write_planning_skill_prompt` + `build_model_prompt_arg` in `run_planning_phase()` with a local variable holding the prompt string passed directly to the model CLI
- [ ] 2.3 Replace `write_implementation_skill_prompt` + `build_model_prompt_arg` in `run_implementation_phase()` with a local variable holding the prompt string passed directly to the model CLI
- [ ] 2.4 Replace `write_user_review_skill_prompt` + `build_model_prompt_arg` in `run_user_review_phase()` with a local variable holding the prompt string passed directly to the model CLI

## 3. Update tests

- [ ] 3.1 Remove or rewrite tests that assert on prompt file existence or content (e.g. `test_user_review_writes_compact_skill_prompt` and equivalent tests for other phases)
