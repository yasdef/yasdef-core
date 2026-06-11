## 1. Create Claude design skill source tree

- [x] 1.1 Create `ai/claude/skills/yasdef-worker-design/` directory with `scripts/` and `assets/` subdirectories.
- [x] 1.2 Copy `ai/codex/skills/yasdef-worker-design/scripts/build_design_context.py` into `ai/claude/skills/yasdef-worker-design/scripts/` byte-for-byte.
- [x] 1.3 Copy `ai/codex/skills/yasdef-worker-design/scripts/check_design_readiness.py` into `ai/claude/skills/yasdef-worker-design/scripts/` byte-for-byte.
- [x] 1.4 Copy `ai/codex/skills/yasdef-worker-design/assets/feature_design_TEMPLATE.md` into `ai/claude/skills/yasdef-worker-design/assets/` byte-for-byte.
- [x] 1.5 Copy `ai/codex/skills/yasdef-worker-design/assets/feature_design_GOLDEN_EXAMPLE.md` into `ai/claude/skills/yasdef-worker-design/assets/` byte-for-byte.
- [x] 1.6 Author `ai/claude/skills/yasdef-worker-design/SKILL.md` — functionally identical to the Codex `SKILL.md` (same 5 inputs, same workflow, same analysis-only / no-runtime-code rule, same sentinel completion line, same helper invocations), adapted to Claude Code skill conventions where they differ from Codex. The Claude `SKILL.md` MUST NOT change the workflow contract or input/output semantics.

## 2. Create Claude slash command

- [x] 2.1 Author `ai/claude/commands/yasdef/design.md` — invokes the `yasdef-worker-design` skill, passes all 5 inputs explicitly (Step, Feature id, Branch, Design output, Runtime implementation plan, Runtime requirements EARS) labeled under an `Inputs:` block. Does NOT read `feature_meta_sync.yaml`. Mirrors the prompt shape produced by `run_design_phase` in `ai/scripts/orchestrator.sh`. If any input is missing, the body instructs the model to stop and ask the user for the missing input.

## 3. Wire Claude design install into init_asdlc_worker.sh

- [x] 3.1 Add `yasdef-worker-design` to the list of skills iterated by `install_claude_skills()` (alongside the existing `yasdef-worker-ai-audit` entry from CRP-133).
- [x] 3.2 Extend `GENERATED_EXCLUDE_PATHS` with `.claude/skills/yasdef-worker-design`.
- [x] 3.3 Extend `DURABLE_COMMIT_PATHS` with `.claude/skills/yasdef-worker-design` and `.claude/commands/yasdef/design.md`.
- [x] 3.4 Verify the install flow: `install_claude_skills` is already called after `install_codex_skills`; no new call sites needed. `install_claude_commands` already copies the entire `$SOURCE_CLAUDE_COMMANDS_DIR/yasdef/` directory, so the new `design.md` is picked up automatically.

## 4. Update install tests

- [x] 4.1 In `tests/ai_scripts/init_asdlc_worker_tests.sh > test_init_bootstraps_existing_git_root`, add `assert_file_exists` assertions for every new Claude design skill artifact installed: `SKILL.md`, both scripts (`build_design_context.py`, `check_design_readiness.py`), both assets (`feature_design_TEMPLATE.md`, `feature_design_GOLDEN_EXAMPLE.md`).
- [x] 4.2 Add `assert_file_exists` for `.claude/commands/yasdef/design.md`.
- [x] 4.3 Add `assert_line_count "1" ".claude/skills/yasdef-worker-design"` for `.git/info/exclude` (the existing `.claude/commands/yasdef` assertion from CRP-133 covers the command directory).
- [x] 4.4 Add `assert_file_tracked_at_head` assertions for every new Claude design skill artifact and for `.claude/commands/yasdef/design.md`.

## 5. Validate

- [x] 5.1 Run `bash tests/ai_scripts/init_asdlc_worker_tests.sh` and confirm pass.
- [x] 5.2 Run the existing design-skill Python tests (whichever shell test file targets `yasdef-worker-design` helpers, if any) and confirm pass — proves the Codex skill is intact.
- [x] 5.3 Run `ai/scripts/init_asdlc_worker.sh` against a scratch target repo; verify `.claude/skills/yasdef-worker-design/` and `.claude/commands/yasdef/design.md` land where expected and that `.codex/skills/yasdef-worker-design/` and the CRP-133 Claude ai_audit tree are also present alongside.
- [ ] 5.4 Manual smoke (deferred for operator verification): set `design | claude | claude-opus-4-7 |  |` in the worker repo's `ai/setup/models.md` and run the orchestrator's design phase end-to-end; verify the Claude design skill is picked up by name and the design artifact is authored.
