## Why

The ASDLC ai_audit phase is currently available as a Codex skill at `ai/codex/skills/yasdef-worker-ai-audit/` and installs into target repos under `.codex/skills/`. Operators who run worker sessions in Claude Code instead of Codex have no equivalent skill installed in their working repo, so they cannot drive the audit phase from inside Claude Code.

This change adds a Claude Code parallel of the existing ai_audit skill — functionally identical to the Codex version (same Python helpers, same workflow contract, same assets) — plus a `/yasdef:audit` slash command, and wires both into the worker bootstrap so a single `init_asdlc_worker.sh` run installs the skill and command alongside the existing Codex skill set.

## What Changes

- Add a Claude Code skill source tree at `ai/claude/skills/yasdef-worker-ai-audit/` mirroring the Codex skill in scope and behavior: `SKILL.md` + four Python scripts (`check_ai_audit_entry.py`, `build_ai_audit_context.py`, `append_follow_up_step.py`, `check_ai_audit_closure.py`) + four assets (`audit_result_TEMPLATE.md`, `audit_result_GOLDEN_EXAMPLE.md`, `raised_question_TEMPLATE.md`, `raised_question_GOLDEN_EXAMPLE.md`). Python scripts and assets are byte-identical copies of their Codex counterparts; `SKILL.md` is allowed to diverge in framing if Claude Code skill conventions require it, as long as the workflow contract, inputs, helper invocations, and outputs match — including invoking `append_follow_up_step.py` for every `create follow-up step` disposition (the helper owns the canonical block shape end-to-end).
- Add a Claude Code slash command at `ai/claude/commands/yasdef/audit.md` that takes all seven inputs explicitly (step, feature id, branch, step plan path, design artifact path, runtime implementation plan path, worker id) — same input shape the Codex orchestrator already produces. The command does not read `feature_meta_sync.yaml`.
- Extend `ai/scripts/init_asdlc_worker.sh` to install the Claude skill into target repos at `<target>/.claude/skills/yasdef-worker-ai-audit/` and the command at `<target>/.claude/commands/yasdef/audit.md` during the same bootstrap pass that installs the Codex skill set.
- Add the new install paths to both `GENERATED_EXCLUDE_PATHS` and `DURABLE_COMMIT_PATHS` so they follow the same tracked-but-excluded convention used for the Codex skills.
- Extend `tests/ai_scripts/init_asdlc_worker_tests.sh` with assertions that the Claude skill files, asset files, script files, and command file are installed, are present in `.git/info/exclude`, and are tracked at HEAD after bootstrap.
- No changes to the Codex skill, the orchestrator, `post_review.sh`, the existing Python helpers, or the existing skill tests.

## Capabilities

### New Capabilities

- `yasdef-worker-ai-audit-claude-skill`: Defines the repo-provided Claude Code skill that owns ASDLC worker ai_audit phase context assembly, two-phase discovery/disposition workflow, and closure validation when the operator runs Claude Code in the worker repo.

### Modified Capabilities

- `worker-runtime-bootstrap`: Installs and tracks the Claude ai_audit skill under `.claude/skills/yasdef-worker-ai-audit/` and the Claude slash command at `.claude/commands/yasdef/audit.md` during target-repo bootstrap, alongside the existing Codex skill set.

## Impact

- `ai/claude/skills/yasdef-worker-ai-audit/**`: new skill source tree (SKILL.md, three Python scripts, four assets).
- `ai/claude/commands/yasdef/audit.md`: new slash command.
- `ai/scripts/init_asdlc_worker.sh`: adds two source-dir globals (`SOURCE_CLAUDE_SKILLS_DIR`, `SOURCE_CLAUDE_COMMANDS_DIR`), extends `GENERATED_EXCLUDE_PATHS` and `DURABLE_COMMIT_PATHS` with `.claude/skills/yasdef-worker-ai-audit` + `.claude/commands/yasdef` (excludes) and `.claude/commands/yasdef/audit.md` (durable), adds `install_claude_skills()` and `install_claude_commands()` functions, hooks them into the install flow next to `install_codex_skills`.
- `tests/ai_scripts/init_asdlc_worker_tests.sh`: new assertions covering Claude skill installation, command installation, exclude-list entries, and HEAD-tracked durability.
- `ai/codex/skills/yasdef-worker-ai-audit/**`: unchanged.
- `ai/scripts/orchestrator.sh`, `ai/scripts/post_review.sh`: unchanged.
- The Claude skill's Python helpers reuse the existing `tests/skills_python_scripts/yasdef_worker_ai_audit_tests.sh` test surface only if the test file is generalized; for this change, the test file remains targeted at the Codex source tree and the install test alone proves the Claude tree exists and is correct.
