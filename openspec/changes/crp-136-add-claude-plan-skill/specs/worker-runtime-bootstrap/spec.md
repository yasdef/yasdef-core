## ADDED Requirements

### Requirement: Worker init installs the Claude planning skill and slash command

The worker init flow (`ai/scripts/init_asdlc_worker.sh`) SHALL install the Claude Code planning skill at `<target-repo>/.claude/skills/yasdef-worker-plan/` and the Claude Code slash command at `<target-repo>/.claude/commands/yasdef/plan.md` during the same bootstrap pass that installs the Codex skill set under `<target-repo>/.codex/skills/` and the Claude ai_audit/design skill sets introduced by CRP-133 / CRP-135.

The Claude planning skill install path SHALL be registered in the init flow's generated-exclude list (so it is added to `<target-repo>/.git/info/exclude`) and the durable-commit list (so it is tracked at HEAD after the bootstrap commit). The new slash command file path `.claude/commands/yasdef/plan.md` SHALL be added to the durable-commit list; the `.claude/commands/yasdef` directory exclude entry from CRP-133 already covers it.

The init flow SHALL fail fast with a descriptive message if the Claude planning skill source directory (`ai/claude/skills/yasdef-worker-plan/`) is missing from the YASDEF source repo.

#### Scenario: Claude planning skill is installed into the target repo
- **WHEN** the operator runs `ai/scripts/init_asdlc_worker.sh` against a target repo
- **THEN** `<target-repo>/.claude/skills/yasdef-worker-plan/SKILL.md` exists
- **THEN** `<target-repo>/.claude/skills/yasdef-worker-plan/scripts/build_plan_context.py` exists
- **THEN** `<target-repo>/.claude/skills/yasdef-worker-plan/scripts/check_planning_readiness.py` exists
- **THEN** `<target-repo>/.claude/skills/yasdef-worker-plan/scripts/sync_step_lars.py` exists
- **THEN** `<target-repo>/.claude/skills/yasdef-worker-plan/assets/step_plan_TEMPLATE.md` exists
- **THEN** `<target-repo>/.claude/skills/yasdef-worker-plan/assets/step_plan_GOLDEN_EXAMPLE.md` exists

#### Scenario: Claude planning slash command is installed into the target repo
- **WHEN** the operator runs `ai/scripts/init_asdlc_worker.sh` against a target repo
- **THEN** `<target-repo>/.claude/commands/yasdef/plan.md` exists

#### Scenario: Codex planning skill installation is unaffected
- **WHEN** the operator runs `ai/scripts/init_asdlc_worker.sh` against a target repo
- **THEN** `<target-repo>/.codex/skills/yasdef-worker-plan/` is installed in full alongside the new Claude planning install paths
- **THEN** the existing Claude ai_audit / design install paths (from CRP-133 / CRP-135) are also installed unchanged
- **THEN** the install order of Codex skills relative to other phases is unchanged

#### Scenario: Claude planning install paths are added to .git/info/exclude
- **WHEN** the operator runs `ai/scripts/init_asdlc_worker.sh` against a target repo
- **THEN** `<target-repo>/.git/info/exclude` contains the line `.claude/skills/yasdef-worker-plan`

#### Scenario: Claude planning install paths are tracked at HEAD after bootstrap commit
- **WHEN** the operator runs `ai/scripts/init_asdlc_worker.sh` against a target repo
- **THEN** all files under `<target-repo>/.claude/skills/yasdef-worker-plan/` are tracked at HEAD in the target repo
- **THEN** `<target-repo>/.claude/commands/yasdef/plan.md` is tracked at HEAD in the target repo

#### Scenario: Init fails fast if Claude planning source tree is missing
- **WHEN** the operator runs `ai/scripts/init_asdlc_worker.sh` against a target repo while the YASDEF source repo is missing `ai/claude/skills/yasdef-worker-plan/`
- **THEN** the init flow fails with a descriptive message naming the missing source directory
- **THEN** no partial Claude planning install is left in the target repo
