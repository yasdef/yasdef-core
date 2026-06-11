## Why

The ASDLC user_review phase is available as a Codex skill at `ai/codex/skills/yasdef-worker-user-review/` and installs into target repos under `.codex/skills/`. CRP-134 made the orchestrator able to dispatch any phase to `claude` based on `ai/setup/models.md`, and CRP-133 / CRP-135 / CRP-136 / CRP-137 established the install pattern for Claude skill parallels. Operators who want to route the user_review phase through Claude Code today have no `.claude/skills/yasdef-worker-user-review/` installed in their worker repo, so the runner change is not usable for the user_review phase.

This change adds a Claude Code parallel of the user_review skill — functionally identical to the Codex version (same Python helper, same workflow contract, same assets) — plus a `/yasdef:user-review` slash command, and wires both into the worker bootstrap so a single `init_asdlc_worker.sh` run installs the user_review skill and command alongside the existing Codex set and the Claude ai_audit/design/plan/implementation skill sets. With this change, all five worker phases have Claude parallels and the Claude rollout is complete.

## What Changes

- Add a Claude Code skill source tree at `ai/claude/skills/yasdef-worker-user-review/` mirroring the Codex skill in scope and behavior: `SKILL.md` + one Python script (`build_user_review_context.py`) + four assets (`review_brief_TEMPLATE.md`, `review_brief_GOLDEN_EXAMPLE.md`, `user_review_TEMPLATE.md`, `user_review_GOLDEN_EXAMPLE.md`). Python script and assets are byte-identical copies of their Codex counterparts; `SKILL.md` is allowed to diverge in framing if Claude Code skill conventions require it, as long as the workflow contract, inputs, helper invocations, and outputs match — including the durable-rules update behavior on `.asdlc_worker/user_review.md`.
- Add a Claude Code slash command at `ai/claude/commands/yasdef/user-review.md` that takes all six inputs explicitly (step, feature id, branch, step plan path, design artifact path, runtime implementation plan path) — same input shape the Codex orchestrator already assembles for the user_review phase in `run_user_review_phase` (`ai/scripts/orchestrator.sh:1966–2021`). The command does not read `feature_meta_sync.yaml`.
- Extend `ai/scripts/init_asdlc_worker.sh` to install the Claude user_review skill into target repos at `<target>/.claude/skills/yasdef-worker-user-review/` and the command at `<target>/.claude/commands/yasdef/user-review.md` during the same bootstrap pass that installs the Codex skill set and the existing Claude skill sets.
- Add `.claude/skills/yasdef-worker-user-review` to `GENERATED_EXCLUDE_PATHS` and `DURABLE_COMMIT_PATHS` (the `.claude/commands/yasdef` directory entries already added by CRP-133 cover the command directory).
- Add `.claude/commands/yasdef/user-review.md` to `DURABLE_COMMIT_PATHS`.
- Extend `tests/ai_scripts/init_asdlc_worker_tests.sh` with assertions that the Claude user_review skill files (SKILL.md, one script, four assets) and command file are installed, are present in `.git/info/exclude`, and are tracked at HEAD after bootstrap.
- No changes to the Codex skill, the orchestrator, `post_review.sh`, `build_phase_cmd.sh`, the existing Python helpers, or the existing skill tests.

## Capabilities

### New Capabilities

- `yasdef-worker-user-review-claude-skill`: Defines the repo-provided Claude Code skill that owns ASDLC worker user_review phase context assembly, review brief drafting, follow-up edits, durable-rules updates on `.asdlc_worker/user_review.md`, and closure when the operator runs Claude Code in the worker repo.

### Modified Capabilities

- `worker-runtime-bootstrap`: Installs and tracks the Claude user_review skill under `.claude/skills/yasdef-worker-user-review/` and the Claude slash command at `.claude/commands/yasdef/user-review.md` during target-repo bootstrap, alongside the existing Codex skill set and the Claude ai_audit/design/plan/implementation skill sets introduced in CRP-133 / CRP-135 / CRP-136 / CRP-137. With this change, all five worker phases have Claude parallels installed.

## Impact

- `ai/claude/skills/yasdef-worker-user-review/**`: new skill source tree (SKILL.md, one Python script, four assets).
- `ai/claude/commands/yasdef/user-review.md`: new slash command.
- `ai/scripts/init_asdlc_worker.sh`: add `yasdef-worker-user-review` to the skill list iterated by `install_claude_skills`, extend `GENERATED_EXCLUDE_PATHS` with `.claude/skills/yasdef-worker-user-review`, extend `DURABLE_COMMIT_PATHS` with `.claude/skills/yasdef-worker-user-review` and `.claude/commands/yasdef/user-review.md`.
- `tests/ai_scripts/init_asdlc_worker_tests.sh`: new assertions covering Claude user_review skill installation, command installation, exclude-list entries, and HEAD-tracked durability.
- `ai/codex/skills/yasdef-worker-user-review/**`: unchanged.
- `ai/scripts/orchestrator.sh`, `ai/scripts/post_review.sh`, `ai/scripts/helpers/build_phase_cmd.sh`: unchanged.
- `ai/setup/models.md`: unchanged (operators opt in by switching the `cmd` column for the `user_review` row to `claude`; that is a runtime config choice, not part of this CRP).
