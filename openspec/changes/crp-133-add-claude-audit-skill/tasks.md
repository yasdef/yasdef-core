## 1. Create Claude skill source tree

- [ ] 1.1 Create `ai/claude/skills/yasdef-worker-ai-audit/` directory with `scripts/` and `assets/` subdirectories.
- [ ] 1.2 Copy `ai/codex/skills/yasdef-worker-ai-audit/scripts/check_ai_audit_entry.py` into `ai/claude/skills/yasdef-worker-ai-audit/scripts/` byte-for-byte.
- [ ] 1.3 Copy `ai/codex/skills/yasdef-worker-ai-audit/scripts/build_ai_audit_context.py` into `ai/claude/skills/yasdef-worker-ai-audit/scripts/` byte-for-byte.
- [ ] 1.4 Copy `ai/codex/skills/yasdef-worker-ai-audit/scripts/check_ai_audit_closure.py` into `ai/claude/skills/yasdef-worker-ai-audit/scripts/` byte-for-byte.
- [ ] 1.5 Copy `ai/codex/skills/yasdef-worker-ai-audit/assets/audit_result_TEMPLATE.md` into `ai/claude/skills/yasdef-worker-ai-audit/assets/` byte-for-byte.
- [ ] 1.6 Copy `ai/codex/skills/yasdef-worker-ai-audit/assets/audit_result_GOLDEN_EXAMPLE.md` into `ai/claude/skills/yasdef-worker-ai-audit/assets/` byte-for-byte.
- [ ] 1.7 Copy `ai/codex/skills/yasdef-worker-ai-audit/assets/raised_question_TEMPLATE.md` into `ai/claude/skills/yasdef-worker-ai-audit/assets/` byte-for-byte.
- [ ] 1.8 Copy `ai/codex/skills/yasdef-worker-ai-audit/assets/raised_question_GOLDEN_EXAMPLE.md` into `ai/claude/skills/yasdef-worker-ai-audit/assets/` byte-for-byte.
- [ ] 1.9 Author `ai/claude/skills/yasdef-worker-ai-audit/SKILL.md` — functionally identical to the Codex SKILL.md (same 7 inputs, same 9-step workflow, same rules, same sentinel), adapted to Claude Code skill conventions where they differ from Codex.

## 2. Create Claude slash command

- [ ] 2.1 Create `ai/claude/commands/yasdef/` directory.
- [ ] 2.2 Author `ai/claude/commands/yasdef/audit.md` — passes all 7 inputs explicitly (Step, Feature id, Branch, Step plan, Design artifact, Runtime implementation plan, Worker id) as the command body invokes the `yasdef-worker-ai-audit` skill. Does NOT read `feature_meta_sync.yaml`. Mirrors the prompt shape produced by `write_ai_audit_skill_prompt` in the orchestrator.

## 3. Wire Claude install into init_asdlc_worker.sh

- [ ] 3.1 Add `SOURCE_CLAUDE_SKILLS_DIR=""` and `SOURCE_CLAUDE_COMMANDS_DIR=""` to the global declarations alongside `SOURCE_CODEX_SKILLS_DIR`.
- [ ] 3.2 Initialize both new source-dir globals after `SOURCE_CODEX_SKILLS_DIR="$SOURCE_ROOT/ai/codex/skills"` is assigned: `SOURCE_CLAUDE_SKILLS_DIR="$SOURCE_ROOT/ai/claude/skills"` and `SOURCE_CLAUDE_COMMANDS_DIR="$SOURCE_ROOT/ai/claude/commands"`.
- [ ] 3.3 Extend `GENERATED_EXCLUDE_PATHS` with `.claude/skills/yasdef-worker-ai-audit` and `.claude/commands/yasdef`.
- [ ] 3.4 Extend `DURABLE_COMMIT_PATHS` with `.claude/skills/yasdef-worker-ai-audit` and `.claude/commands/yasdef/audit.md`.
- [ ] 3.5 Add `install_claude_skills()` function mirroring `install_codex_skills()`: iterates a single-entry list `[yasdef-worker-ai-audit]`, fails fast if source missing, calls `remove_generated_path` + `copy_dir_contents` to install under `<target>/.claude/skills/`.
- [ ] 3.6 Add `install_claude_commands()` function: copies `$SOURCE_CLAUDE_COMMANDS_DIR/yasdef/` to `<target>/.claude/commands/yasdef/` using `remove_generated_path` + `copy_dir_contents`; fails fast if source missing.
- [ ] 3.7 Call `install_claude_skills` and `install_claude_commands` from the install flow immediately after `install_codex_skills`.

## 4. Update install tests

- [ ] 4.1 In `tests/ai_scripts/init_asdlc_worker_tests.sh > test_init_bootstraps_existing_git_root`, add `assert_file_exists` assertions for every Claude skill artifact installed (`SKILL.md`, three scripts, four assets).
- [ ] 4.2 Add `assert_file_exists` for `.claude/commands/yasdef/audit.md`.
- [ ] 4.3 Add `assert_line_count "1" ".claude/skills/yasdef-worker-ai-audit"` and `assert_line_count "1" ".claude/commands/yasdef"` for `.git/info/exclude`.
- [ ] 4.4 Add `assert_file_tracked_at_head` assertions for every Claude skill artifact and for `.claude/commands/yasdef/audit.md`.

## 5. Validate

- [ ] 5.1 Run `bash tests/ai_scripts/init_asdlc_worker_tests.sh` and confirm pass.
- [ ] 5.2 Run `bash tests/skills_python_scripts/yasdef_worker_ai_audit_tests.sh` and confirm pass (unchanged — proves the Codex skill is intact).
- [ ] 5.3 Run `ai/scripts/init_asdlc_worker.sh` against a scratch target repo; verify `.claude/skills/yasdef-worker-ai-audit/` and `.claude/commands/yasdef/audit.md` land where expected and that `.codex/skills/yasdef-worker-ai-audit/` is also present alongside.
