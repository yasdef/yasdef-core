## Why

The ASDLC planning phase is available as a Codex skill at `ai/codex/skills/yasdef-worker-plan/` and installs into target repos under `.codex/skills/`. CRP-134 made the orchestrator able to dispatch any phase to `claude` based on `ai/setup/models.md`, and CRP-133 / CRP-135 established the install pattern for Claude skill parallels. Operators who want to route the planning phase through Claude Code today have no `.claude/skills/yasdef-worker-plan/` installed in their worker repo, so the runner change is not usable for the planning phase.

This change adds a Claude Code parallel of the planning skill — functionally identical to the Codex version (same Python helpers, same workflow contract, same assets) — plus a `/yasdef:plan` slash command, and wires both into the worker bootstrap so a single `init_asdlc_worker.sh` run installs the planning skill and command alongside the existing Codex set and the Claude ai_audit/design skill sets.

## What Changes

- Add a Claude Code skill source tree at `ai/claude/skills/yasdef-worker-plan/` mirroring the Codex skill in scope and behavior: `SKILL.md` + three Python scripts (`build_plan_context.py`, `check_planning_readiness.py`, `sync_step_lars.py`) + two assets (`step_plan_TEMPLATE.md`, `step_plan_GOLDEN_EXAMPLE.md`). Python scripts and assets are byte-identical copies of their Codex counterparts; `SKILL.md` is allowed to diverge in framing if Claude Code skill conventions require it, as long as the workflow contract, inputs, helper invocations, and outputs match.
- Add a Claude Code slash command at `ai/claude/commands/yasdef/plan.md` that takes all eight inputs explicitly (step, feature id, branch, design artifact path, step plan output path, runtime implementation plan path, open-questions ledger path, blockers ledger path) — same input shape the Codex orchestrator already assembles for the planning phase in `run_planning_phase` (`ai/scripts/orchestrator.sh:683–771`). The command does not read `feature_meta_sync.yaml`.
- Extend `ai/scripts/init_asdlc_worker.sh` to install the Claude planning skill into target repos at `<target>/.claude/skills/yasdef-worker-plan/` and the command at `<target>/.claude/commands/yasdef/plan.md` during the same bootstrap pass that installs the Codex skill set and the existing Claude ai_audit/design skill sets.
- Add `.claude/skills/yasdef-worker-plan` to `GENERATED_EXCLUDE_PATHS` and `DURABLE_COMMIT_PATHS` (the `.claude/commands/yasdef` directory entries already added by CRP-133 cover the command directory).
- Add `.claude/commands/yasdef/plan.md` to `DURABLE_COMMIT_PATHS`.
- Extend `tests/ai_scripts/init_asdlc_worker_tests.sh` with assertions that the Claude planning skill files (SKILL.md, three scripts, two assets) and command file are installed, are present in `.git/info/exclude`, and are tracked at HEAD after bootstrap.
- No changes to the Codex skill, the orchestrator, `post_review.sh`, `build_phase_cmd.sh`, the existing Python helpers, or the existing skill tests.

## Capabilities

### New Capabilities

- `yasdef-worker-plan-claude-skill`: Defines the repo-provided Claude Code skill that owns ASDLC worker planning phase context assembly, step plan authoring, readiness/ledger validation, and closure when the operator runs Claude Code in the worker repo.

### Modified Capabilities

- `worker-runtime-bootstrap`: Installs and tracks the Claude planning skill under `.claude/skills/yasdef-worker-plan/` and the Claude slash command at `.claude/commands/yasdef/plan.md` during target-repo bootstrap, alongside the existing Codex skill set and the Claude ai_audit/design skill sets introduced in CRP-133 / CRP-135.

## Impact

- `ai/claude/skills/yasdef-worker-plan/**`: new skill source tree (SKILL.md, three Python scripts, two assets).
- `ai/claude/commands/yasdef/plan.md`: new slash command.
- `ai/scripts/init_asdlc_worker.sh`: add `yasdef-worker-plan` to the skill list iterated by `install_claude_skills`, extend `GENERATED_EXCLUDE_PATHS` with `.claude/skills/yasdef-worker-plan`, extend `DURABLE_COMMIT_PATHS` with `.claude/skills/yasdef-worker-plan` and `.claude/commands/yasdef/plan.md`.
- `tests/ai_scripts/init_asdlc_worker_tests.sh`: new assertions covering Claude planning skill installation, command installation, exclude-list entries, and HEAD-tracked durability.
- `ai/codex/skills/yasdef-worker-plan/**`: unchanged.
- `ai/scripts/orchestrator.sh`, `ai/scripts/post_review.sh`, `ai/scripts/helpers/build_phase_cmd.sh`: unchanged.
- `ai/setup/models.md`: unchanged (operators opt in by switching the `cmd` column for the `planning` row to `claude`; that is a runtime config choice, not part of this CRP).
