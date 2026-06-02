## 1. Create Claude planning skill source tree

- [ ] 1.1 Create `ai/claude/skills/yasdef-worker-plan/` directory with `scripts/` and `assets/` subdirectories.
- [ ] 1.2 Copy `ai/codex/skills/yasdef-worker-plan/scripts/build_plan_context.py` into `ai/claude/skills/yasdef-worker-plan/scripts/` byte-for-byte.
- [ ] 1.3 Copy `ai/codex/skills/yasdef-worker-plan/scripts/check_planning_readiness.py` into `ai/claude/skills/yasdef-worker-plan/scripts/` byte-for-byte.
- [ ] 1.4 Copy `ai/codex/skills/yasdef-worker-plan/scripts/sync_step_lars.py` into `ai/claude/skills/yasdef-worker-plan/scripts/` byte-for-byte.
- [ ] 1.5 Copy `ai/codex/skills/yasdef-worker-plan/assets/step_plan_TEMPLATE.md` into `ai/claude/skills/yasdef-worker-plan/assets/` byte-for-byte.
- [ ] 1.6 Copy `ai/codex/skills/yasdef-worker-plan/assets/step_plan_GOLDEN_EXAMPLE.md` into `ai/claude/skills/yasdef-worker-plan/assets/` byte-for-byte.
- [ ] 1.7 Author `ai/claude/skills/yasdef-worker-plan/SKILL.md` — functionally identical to the Codex `SKILL.md` (same 8 inputs, same iteration workflow, same readiness invariants, same LARS-sync responsibilities, same analysis-only / no-runtime-code rule, same sentinel completion line, same helper invocations), adapted to Claude Code skill conventions where they differ from Codex. The Claude `SKILL.md` MUST NOT change the workflow contract or input/output semantics.

## 2. Create Claude slash command

- [ ] 2.1 Author `ai/claude/commands/yasdef/plan.md` — invokes the `yasdef-worker-plan` skill, passes all 8 inputs explicitly (Step, Feature id, Branch, Design artifact, Step plan output, Runtime implementation plan, Open questions ledger, Blockers ledger) labeled under an `Inputs:` block. Does NOT read `feature_meta_sync.yaml`. Mirrors the prompt shape produced by `run_planning_phase` in `ai/scripts/orchestrator.sh`. If any input is missing, the body instructs the model to stop and ask the user for the missing input.

## 3. Wire Claude planning install into init_asdlc_worker.sh

- [ ] 3.1 Add `yasdef-worker-plan` to the list of skills iterated by `install_claude_skills()` (alongside the existing entries from CRP-133 / CRP-135).
- [ ] 3.2 Extend `GENERATED_EXCLUDE_PATHS` with `.claude/skills/yasdef-worker-plan`.
- [ ] 3.3 Extend `DURABLE_COMMIT_PATHS` with `.claude/skills/yasdef-worker-plan` and `.claude/commands/yasdef/plan.md`.
- [ ] 3.4 Verify the install flow: `install_claude_skills` is already called after `install_codex_skills`; no new call sites needed. `install_claude_commands` already copies the entire `$SOURCE_CLAUDE_COMMANDS_DIR/yasdef/` directory, so the new `plan.md` is picked up automatically.

## 4. Update install tests

- [ ] 4.1 In `tests/ai_scripts/init_asdlc_worker_tests.sh > test_init_bootstraps_existing_git_root`, add `assert_file_exists` assertions for every new Claude planning skill artifact installed: `SKILL.md`, all three scripts (`build_plan_context.py`, `check_planning_readiness.py`, `sync_step_lars.py`), both assets (`step_plan_TEMPLATE.md`, `step_plan_GOLDEN_EXAMPLE.md`).
- [ ] 4.2 Add `assert_file_exists` for `.claude/commands/yasdef/plan.md`.
- [ ] 4.3 Add `assert_line_count "1" ".claude/skills/yasdef-worker-plan"` for `.git/info/exclude` (the existing `.claude/commands/yasdef` assertion from CRP-133 covers the command directory).
- [ ] 4.4 Add `assert_file_tracked_at_head` assertions for every new Claude planning skill artifact and for `.claude/commands/yasdef/plan.md`.

## 5. Validate

- [ ] 5.1 Run `bash tests/ai_scripts/init_asdlc_worker_tests.sh` and confirm pass.
- [ ] 5.2 Run the existing planning-skill Python tests (whichever shell test file targets `yasdef-worker-plan` helpers, if any) and confirm pass — proves the Codex skill is intact.
- [ ] 5.3 Run `ai/scripts/init_asdlc_worker.sh` against a scratch target repo; verify `.claude/skills/yasdef-worker-plan/` and `.claude/commands/yasdef/plan.md` land where expected and that `.codex/skills/yasdef-worker-plan/` and the existing CRP-133 / CRP-135 Claude trees are also present alongside.
- [ ] 5.4 Manual smoke (deferred for operator verification): set `planning | claude | claude-opus-4-7 |  |` in the worker repo's `ai/setup/models.md` and run the orchestrator's planning phase end-to-end; verify the Claude planning skill is picked up by name, the step plan artifact is authored, and the readiness gate clears.
