## ADDED Requirements

### Requirement: Worker init installs the Claude implementation skill and slash command

The worker init flow (`ai/scripts/init_asdlc_worker.sh`) SHALL install the Claude Code implementation skill at `<target-repo>/.claude/skills/yasdef-worker-implementation/` and the Claude Code slash command at `<target-repo>/.claude/commands/yasdef/implementation.md` during the same bootstrap pass that installs the Codex skill set under `<target-repo>/.codex/skills/` and the Claude ai_audit/design/plan skill sets introduced by CRP-133 / CRP-135 / CRP-136.

The Claude implementation skill install path SHALL be registered in the init flow's generated-exclude list (so it is added to `<target-repo>/.git/info/exclude`) and the durable-commit list (so it is tracked at HEAD after the bootstrap commit). The new slash command file path `.claude/commands/yasdef/implementation.md` SHALL be added to the durable-commit list; the `.claude/commands/yasdef` directory exclude entry from CRP-133 already covers it.

The init flow SHALL fail fast with a descriptive message if the Claude implementation skill source directory (`ai/claude/skills/yasdef-worker-implementation/`) is missing from the YASDEF source repo.

#### Scenario: Claude implementation skill is installed into the target repo
- **WHEN** the operator runs `ai/scripts/init_asdlc_worker.sh` against a target repo
- **THEN** `<target-repo>/.claude/skills/yasdef-worker-implementation/SKILL.md` exists
- **THEN** `<target-repo>/.claude/skills/yasdef-worker-implementation/scripts/build_implementation_context.py` exists
- **THEN** `<target-repo>/.claude/skills/yasdef-worker-implementation/scripts/check_implementation_readiness.py` exists
- **THEN** `<target-repo>/.claude/skills/yasdef-worker-implementation/` contains no `assets/` subdirectory

#### Scenario: Claude implementation slash command is installed into the target repo
- **WHEN** the operator runs `ai/scripts/init_asdlc_worker.sh` against a target repo
- **THEN** `<target-repo>/.claude/commands/yasdef/implementation.md` exists

#### Scenario: Codex implementation skill installation is unaffected
- **WHEN** the operator runs `ai/scripts/init_asdlc_worker.sh` against a target repo
- **THEN** `<target-repo>/.codex/skills/yasdef-worker-implementation/` is installed in full alongside the new Claude implementation install paths
- **THEN** the existing Claude ai_audit / design / plan install paths (from CRP-133 / CRP-135 / CRP-136) are also installed unchanged
- **THEN** the install order of Codex skills relative to other phases is unchanged

#### Scenario: Claude implementation install paths are added to .git/info/exclude
- **WHEN** the operator runs `ai/scripts/init_asdlc_worker.sh` against a target repo
- **THEN** `<target-repo>/.git/info/exclude` contains the line `.claude/skills/yasdef-worker-implementation`

#### Scenario: Claude implementation install paths are tracked at HEAD after bootstrap commit
- **WHEN** the operator runs `ai/scripts/init_asdlc_worker.sh` against a target repo
- **THEN** all files under `<target-repo>/.claude/skills/yasdef-worker-implementation/` are tracked at HEAD in the target repo
- **THEN** `<target-repo>/.claude/commands/yasdef/implementation.md` is tracked at HEAD in the target repo

#### Scenario: Init fails fast if Claude implementation source tree is missing
- **WHEN** the operator runs `ai/scripts/init_asdlc_worker.sh` against a target repo while the YASDEF source repo is missing `ai/claude/skills/yasdef-worker-implementation/`
- **THEN** the init flow fails with a descriptive message naming the missing source directory
- **THEN** no partial Claude implementation install is left in the target repo
