## Why

The ASDLC design phase is available as a Codex skill at `ai/codex/skills/yasdef-worker-design/` and installs into target repos under `.codex/skills/`. CRP-134 made the orchestrator able to dispatch any phase to `claude` based on `ai/setup/models.md`, and CRP-133 proved the install pattern by adding the Claude parallel of the ai_audit skill. Operators who want to route the design phase through Claude Code today have no `.claude/skills/yasdef-worker-design/` installed in their worker repo, so the runner change is not usable for the design phase.

This change adds a Claude Code parallel of the design skill — functionally identical to the Codex version (same Python helpers, same workflow contract, same assets) — plus a `/yasdef:design` slash command, and wires both into the worker bootstrap so a single `init_asdlc_worker.sh` run installs the design skill and command alongside the existing Codex set and the Claude ai_audit skill set.

## What Changes

- Add a Claude Code skill source tree at `ai/claude/skills/yasdef-worker-design/` mirroring the Codex skill in scope and behavior: `SKILL.md` + two Python scripts (`build_design_context.py`, `check_design_readiness.py`) + two assets (`feature_design_TEMPLATE.md`, `feature_design_GOLDEN_EXAMPLE.md`). Python scripts and assets are byte-identical copies of their Codex counterparts; `SKILL.md` is allowed to diverge in framing if Claude Code skill conventions require it, as long as the workflow contract, inputs, helper invocations, and outputs match.
- Add a Claude Code slash command at `ai/claude/commands/yasdef/design.md` that takes all five inputs explicitly (step, feature id, branch, design output path, runtime implementation plan path, runtime requirements EARS path) — same input shape the Codex orchestrator already assembles for the design phase in `run_design_phase` (orchestrator.sh:778–845). The command does not read `feature_meta_sync.yaml`.
- Extend `ai/scripts/init_asdlc_worker.sh` to install the Claude design skill into target repos at `<target>/.claude/skills/yasdef-worker-design/` and the command at `<target>/.claude/commands/yasdef/design.md` during the same bootstrap pass that installs the Codex skill set and the Claude ai_audit skill set.
- Add `.claude/skills/yasdef-worker-design` to `GENERATED_EXCLUDE_PATHS` and `DURABLE_COMMIT_PATHS` (the `.claude/commands/yasdef` directory entries already added by CRP-133 cover the command directory).
- Add `.claude/commands/yasdef/design.md` to `DURABLE_COMMIT_PATHS`.
- Extend `tests/ai_scripts/init_asdlc_worker_tests.sh` with assertions that the Claude design skill files (SKILL.md, two scripts, two assets) and command file are installed, are present in `.git/info/exclude`, and are tracked at HEAD after bootstrap.
- No changes to the Codex skill, the orchestrator, `post_review.sh`, `build_phase_cmd.sh`, the existing Python helpers, or the existing skill tests.

## Capabilities

### New Capabilities

- `yasdef-worker-design-claude-skill`: Defines the repo-provided Claude Code skill that owns ASDLC worker design phase context assembly, design-artifact authoring/validation, and closure when the operator runs Claude Code in the worker repo.

### Modified Capabilities

- `worker-runtime-bootstrap`: Installs and tracks the Claude design skill under `.claude/skills/yasdef-worker-design/` and the Claude slash command at `.claude/commands/yasdef/design.md` during target-repo bootstrap, alongside the existing Codex skill set and the Claude ai_audit skill set introduced in CRP-133.

## Impact

- `ai/claude/skills/yasdef-worker-design/**`: new skill source tree (SKILL.md, two Python scripts, two assets).
- `ai/claude/commands/yasdef/design.md`: new slash command.
- `ai/scripts/init_asdlc_worker.sh`: add `yasdef-worker-design` to the skill list iterated by `install_claude_skills`, extend `GENERATED_EXCLUDE_PATHS` with `.claude/skills/yasdef-worker-design`, extend `DURABLE_COMMIT_PATHS` with `.claude/skills/yasdef-worker-design` and `.claude/commands/yasdef/design.md`.
- `tests/ai_scripts/init_asdlc_worker_tests.sh`: new assertions covering Claude design skill installation, command installation, exclude-list entries, and HEAD-tracked durability.
- `ai/codex/skills/yasdef-worker-design/**`: unchanged.
- `ai/scripts/orchestrator.sh`, `ai/scripts/post_review.sh`, `ai/scripts/helpers/build_phase_cmd.sh`: unchanged.
- `ai/setup/models.md`: unchanged (operators opt in by switching the `cmd` column for the `design` row to `claude`; that is a runtime config choice, not part of this CRP).
