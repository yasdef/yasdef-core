## Why

The ASDLC implementation phase is available as a Codex skill at `ai/codex/skills/yasdef-worker-implementation/` and installs into target repos under `.codex/skills/`. CRP-134 made the orchestrator able to dispatch any phase to `claude` based on `ai/setup/models.md`, and CRP-133 / CRP-135 / CRP-136 established the install pattern for Claude skill parallels. Operators who want to route the implementation phase through Claude Code today have no `.claude/skills/yasdef-worker-implementation/` installed in their worker repo, so the runner change is not usable for the implementation phase.

This change adds a Claude Code parallel of the implementation skill — functionally identical to the Codex version (same Python helpers, same workflow contract) — plus a `/yasdef:implementation` slash command, and wires both into the worker bootstrap so a single `init_asdlc_worker.sh` run installs the implementation skill and command alongside the existing Codex set and the Claude ai_audit/design/plan skill sets.

## What Changes

- Add a Claude Code skill source tree at `ai/claude/skills/yasdef-worker-implementation/` mirroring the Codex skill in scope and behavior: `SKILL.md` + two Python scripts (`build_implementation_context.py`, `check_implementation_readiness.py`). The implementation skill has no `assets/` subdirectory in the Codex source, so none is created for the Claude parallel either. Python scripts are byte-identical copies of their Codex counterparts; `SKILL.md` is allowed to diverge in framing if Claude Code skill conventions require it, as long as the workflow contract, inputs, helper invocations, and outputs match.
- Add a Claude Code slash command at `ai/claude/commands/yasdef/implementation.md` that takes all six inputs explicitly (step, feature id, branch, step plan path, design artifact path, runtime implementation plan path) — same input shape the Codex orchestrator already assembles for the implementation phase in `run_implementation_phase` (`ai/scripts/orchestrator.sh:1893–1960`). The command does not read `feature_meta_sync.yaml`.
- Extend `ai/scripts/init_asdlc_worker.sh` to install the Claude implementation skill into target repos at `<target>/.claude/skills/yasdef-worker-implementation/` and the command at `<target>/.claude/commands/yasdef/implementation.md` during the same bootstrap pass that installs the Codex skill set and the existing Claude skill sets.
- Add `.claude/skills/yasdef-worker-implementation` to `GENERATED_EXCLUDE_PATHS` and `DURABLE_COMMIT_PATHS` (the `.claude/commands/yasdef` directory entries already added by CRP-133 cover the command directory).
- Add `.claude/commands/yasdef/implementation.md` to `DURABLE_COMMIT_PATHS`.
- Extend `tests/ai_scripts/init_asdlc_worker_tests.sh` with assertions that the Claude implementation skill files (SKILL.md, two scripts) and command file are installed, are present in `.git/info/exclude`, and are tracked at HEAD after bootstrap.
- No changes to the Codex skill, the orchestrator, `post_review.sh`, `build_phase_cmd.sh`, the existing Python helpers, or the existing skill tests.

## Capabilities

### New Capabilities

- `yasdef-worker-implementation-claude-skill`: Defines the repo-provided Claude Code skill that owns ASDLC worker implementation phase context assembly, runtime-code editing, step-plan checklist updates, and readiness/closure validation when the operator runs Claude Code in the worker repo.

### Modified Capabilities

- `worker-runtime-bootstrap`: Installs and tracks the Claude implementation skill under `.claude/skills/yasdef-worker-implementation/` and the Claude slash command at `.claude/commands/yasdef/implementation.md` during target-repo bootstrap, alongside the existing Codex skill set and the Claude ai_audit/design/plan skill sets introduced in CRP-133 / CRP-135 / CRP-136.

## Impact

- `ai/claude/skills/yasdef-worker-implementation/**`: new skill source tree (SKILL.md, two Python scripts). No assets directory (parity with Codex).
- `ai/claude/commands/yasdef/implementation.md`: new slash command.
- `ai/scripts/init_asdlc_worker.sh`: add `yasdef-worker-implementation` to the skill list iterated by `install_claude_skills`, extend `GENERATED_EXCLUDE_PATHS` with `.claude/skills/yasdef-worker-implementation`, extend `DURABLE_COMMIT_PATHS` with `.claude/skills/yasdef-worker-implementation` and `.claude/commands/yasdef/implementation.md`.
- `tests/ai_scripts/init_asdlc_worker_tests.sh`: new assertions covering Claude implementation skill installation, command installation, exclude-list entries, and HEAD-tracked durability.
- `ai/codex/skills/yasdef-worker-implementation/**`: unchanged.
- `ai/scripts/orchestrator.sh`, `ai/scripts/post_review.sh`, `ai/scripts/helpers/build_phase_cmd.sh`: unchanged.
- `ai/setup/models.md`: unchanged (operators opt in by switching the `cmd` column for the `implementation` row to `claude`; that is a runtime config choice, not part of this CRP).
