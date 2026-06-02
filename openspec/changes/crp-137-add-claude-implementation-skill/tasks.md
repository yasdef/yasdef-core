## 1. Create Claude implementation skill source tree

- [ ] 1.1 Create `ai/claude/skills/yasdef-worker-implementation/` directory with a `scripts/` subdirectory. Do NOT create an `assets/` subdirectory (parity with the Codex skill).
- [ ] 1.2 Copy `ai/codex/skills/yasdef-worker-implementation/scripts/build_implementation_context.py` into `ai/claude/skills/yasdef-worker-implementation/scripts/` byte-for-byte.
- [ ] 1.3 Copy `ai/codex/skills/yasdef-worker-implementation/scripts/check_implementation_readiness.py` into `ai/claude/skills/yasdef-worker-implementation/scripts/` byte-for-byte.
- [ ] 1.4 Author `ai/claude/skills/yasdef-worker-implementation/SKILL.md` — functionally identical to the Codex `SKILL.md` (same 6 inputs, same executing-phase semantics, same step-plan checklist update behavior, same readiness invariants, same sentinel completion line, same helper invocations), adapted to Claude Code skill conventions where they differ from Codex. The Claude `SKILL.md` MUST NOT change the workflow contract or input/output semantics.

## 2. Create Claude slash command

- [ ] 2.1 Author `ai/claude/commands/yasdef/implementation.md` — invokes the `yasdef-worker-implementation` skill, passes all 6 inputs explicitly (Step, Feature id, Branch, Step plan, Design artifact, Runtime implementation plan) labeled under an `Inputs:` block. Does NOT read `feature_meta_sync.yaml`. Mirrors the prompt shape produced by `run_implementation_phase` in `ai/scripts/orchestrator.sh`. If any input is missing, the body instructs the model to stop and ask the user for the missing input.

## 3. Wire Claude implementation install into init_asdlc_worker.sh

- [ ] 3.1 Add `yasdef-worker-implementation` to the list of skills iterated by `install_claude_skills()` (alongside the existing entries from CRP-133 / CRP-135 / CRP-136).
- [ ] 3.2 Extend `GENERATED_EXCLUDE_PATHS` with `.claude/skills/yasdef-worker-implementation`.
- [ ] 3.3 Extend `DURABLE_COMMIT_PATHS` with `.claude/skills/yasdef-worker-implementation` and `.claude/commands/yasdef/implementation.md`.
- [ ] 3.4 Verify the install flow: `install_claude_skills` is already called after `install_codex_skills`; no new call sites needed. `install_claude_commands` already copies the entire `$SOURCE_CLAUDE_COMMANDS_DIR/yasdef/` directory, so the new `implementation.md` is picked up automatically.

## 4. Update install tests

- [ ] 4.1 In `tests/ai_scripts/init_asdlc_worker_tests.sh > test_init_bootstraps_existing_git_root`, add `assert_file_exists` assertions for every new Claude implementation skill artifact installed: `SKILL.md`, both scripts (`build_implementation_context.py`, `check_implementation_readiness.py`).
- [ ] 4.2 Add `assert_file_exists` for `.claude/commands/yasdef/implementation.md`.
- [ ] 4.3 Add `assert_line_count "1" ".claude/skills/yasdef-worker-implementation"` for `.git/info/exclude` (the existing `.claude/commands/yasdef` assertion from CRP-133 covers the command directory).
- [ ] 4.4 Add `assert_file_tracked_at_head` assertions for every new Claude implementation skill artifact and for `.claude/commands/yasdef/implementation.md`.
- [ ] 4.5 Optional: add an assertion that `<target-repo>/.claude/skills/yasdef-worker-implementation/assets/` does NOT exist, mirroring the Codex parity rule.

## 5. Validate

- [ ] 5.1 Run `bash tests/ai_scripts/init_asdlc_worker_tests.sh` and confirm pass.
- [ ] 5.2 Run the existing implementation-skill Python tests (whichever shell test file targets `yasdef-worker-implementation` helpers, if any) and confirm pass — proves the Codex skill is intact.
- [ ] 5.3 Run `ai/scripts/init_asdlc_worker.sh` against a scratch target repo; verify `.claude/skills/yasdef-worker-implementation/` and `.claude/commands/yasdef/implementation.md` land where expected and that `.codex/skills/yasdef-worker-implementation/` and the existing CRP-133 / CRP-135 / CRP-136 Claude trees are also present alongside.
- [ ] 5.4 Manual smoke (deferred for operator verification): set `implementation | claude | claude-opus-4-7 |  |` in the worker repo's `ai/setup/models.md` and run the orchestrator's implementation phase end-to-end; verify the Claude implementation skill is picked up by name, runtime code edits are produced, the step-plan checklist updates, and the readiness gate clears.
