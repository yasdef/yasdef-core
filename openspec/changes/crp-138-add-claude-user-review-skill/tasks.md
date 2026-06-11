## 1. Create Claude user_review skill source tree

- [x] 1.1 Create `ai/claude/skills/yasdef-worker-user-review/` directory with `scripts/` and `assets/` subdirectories.
- [x] 1.2 Copy `ai/codex/skills/yasdef-worker-user-review/scripts/build_user_review_context.py` into `ai/claude/skills/yasdef-worker-user-review/scripts/` byte-for-byte.
- [x] 1.3 Copy `ai/codex/skills/yasdef-worker-user-review/assets/review_brief_TEMPLATE.md` into `ai/claude/skills/yasdef-worker-user-review/assets/` byte-for-byte.
- [x] 1.4 Copy `ai/codex/skills/yasdef-worker-user-review/assets/review_brief_GOLDEN_EXAMPLE.md` into `ai/claude/skills/yasdef-worker-user-review/assets/` byte-for-byte.
- [x] 1.5 Copy `ai/codex/skills/yasdef-worker-user-review/assets/user_review_TEMPLATE.md` into `ai/claude/skills/yasdef-worker-user-review/assets/` byte-for-byte.
- [x] 1.6 Copy `ai/codex/skills/yasdef-worker-user-review/assets/user_review_GOLDEN_EXAMPLE.md` into `ai/claude/skills/yasdef-worker-user-review/assets/` byte-for-byte.
- [x] 1.7 Author `ai/claude/skills/yasdef-worker-user-review/SKILL.md` — functionally identical to the Codex `SKILL.md` (same 6 inputs, same executing-phase semantics, same durable-rules update behavior on `.asdlc_worker/user_review.md`, same review-brief authoring shape, same sentinel completion line, same helper invocations), adapted to Claude Code skill conventions where they differ from Codex. The Claude `SKILL.md` MUST NOT change the workflow contract or input/output semantics.

## 2. Create Claude slash command

- [x] 2.1 Author `ai/claude/commands/yasdef/user-review.md` — invokes the `yasdef-worker-user-review` skill, passes all 6 inputs explicitly (Step, Feature id, Branch, Step plan, Design artifact, Runtime implementation plan) labeled under an `Inputs:` block. Does NOT read `feature_meta_sync.yaml`. Mirrors the prompt shape produced by `run_user_review_phase` in `ai/scripts/orchestrator.sh`. If any input is missing, the body instructs the model to stop and ask the user for the missing input. Filename uses hyphen (`user-review.md`) to match the skill directory naming convention.

## 3. Wire Claude user_review install into init_asdlc_worker.sh

- [x] 3.1 Add `yasdef-worker-user-review` to the list of skills iterated by `install_claude_skills()` (alongside all four entries from CRP-133 / CRP-135 / CRP-136 / CRP-137).
- [x] 3.2 Extend `GENERATED_EXCLUDE_PATHS` with `.claude/skills/yasdef-worker-user-review`.
- [x] 3.3 Extend `DURABLE_COMMIT_PATHS` with `.claude/skills/yasdef-worker-user-review` and `.claude/commands/yasdef/user-review.md`.
- [x] 3.4 Verify the install flow: `install_claude_skills` is already called after `install_codex_skills`; no new call sites needed. `install_claude_commands` already copies the entire `$SOURCE_CLAUDE_COMMANDS_DIR/yasdef/` directory, so the new `user-review.md` is picked up automatically.

## 4. Update install tests

- [x] 4.1 In `tests/ai_scripts/init_asdlc_worker_tests.sh > test_init_bootstraps_existing_git_root`, add `assert_file_exists` assertions for every new Claude user_review skill artifact installed: `SKILL.md`, the one script (`build_user_review_context.py`), all four assets (`review_brief_TEMPLATE.md`, `review_brief_GOLDEN_EXAMPLE.md`, `user_review_TEMPLATE.md`, `user_review_GOLDEN_EXAMPLE.md`).
- [x] 4.2 Add `assert_file_exists` for `.claude/commands/yasdef/user-review.md`.
- [x] 4.3 Add `assert_line_count "1" ".claude/skills/yasdef-worker-user-review"` for `.git/info/exclude` (the existing `.claude/commands/yasdef` assertion from CRP-133 covers the command directory).
- [x] 4.4 Add `assert_file_tracked_at_head` assertions for every new Claude user_review skill artifact and for `.claude/commands/yasdef/user-review.md`.
- [x] 4.5 Optional: add a final "full Claude phase parity" assertion that loops over the five expected Claude skill directories and the five expected Claude slash command files and asserts each exists — a regression-catching sanity check now that the series is complete.

## 5. Validate

- [x] 5.1 Run `bash tests/ai_scripts/init_asdlc_worker_tests.sh` and confirm pass.
- [x] 5.2 Run the existing user_review-skill Python tests (whichever shell test file targets `yasdef-worker-user-review` helpers, if any) and confirm pass — proves the Codex skill is intact.
- [x] 5.3 Run `ai/scripts/init_asdlc_worker.sh` against a scratch target repo; verify `.claude/skills/yasdef-worker-user-review/` and `.claude/commands/yasdef/user-review.md` land where expected and that `.codex/skills/yasdef-worker-user-review/` and all four prior Claude trees (CRP-133 / CRP-135 / CRP-136 / CRP-137) are also present alongside.
- [ ] 5.4 Manual smoke (deferred for operator verification): set `user_review | claude | claude-opus-4-7 |  |` in the worker repo's `ai/setup/models.md` and run the orchestrator's user_review phase end-to-end; verify the Claude user_review skill is picked up by name, follow-up edits are produced, the durable-rules update behavior on `.asdlc_worker/user_review.md` fires when feedback yields a rule, and the phase closes cleanly handing off to ai_audit.
- [ ] 5.5 Full-stack smoke (deferred): in a worker repo, set ALL five phase rows in `ai/setup/models.md` to `cmd=claude`, and run a complete step end-to-end (design → planning → implementation → user_review → ai_audit). Verify every phase opens the Claude UI, every phase closes correctly, the post_review history entry reflects total=0 for all five phases (claude phases contribute 0 to the token sum per the CRP-134 behavior), and the orchestrator transitions between phases without error.
