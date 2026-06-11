## ADDED Requirements

### Requirement: Worker init installs the Claude design skill and slash command

The worker init flow (`ai/scripts/init_asdlc_worker.sh`) SHALL install the Claude Code design skill at `<target-repo>/.claude/skills/yasdef-worker-design/` and the Claude Code slash command at `<target-repo>/.claude/commands/yasdef/design.md` during the same bootstrap pass that installs the Codex skill set under `<target-repo>/.codex/skills/` and the Claude ai_audit skill set introduced by CRP-133.

The Claude design skill install path SHALL be registered in the init flow's generated-exclude list (so it is added to `<target-repo>/.git/info/exclude`) and the durable-commit list (so it is tracked at HEAD after the bootstrap commit). The new slash command file path `.claude/commands/yasdef/design.md` SHALL be added to the durable-commit list; the `.claude/commands/yasdef` directory exclude entry from CRP-133 already covers it.

The init flow SHALL fail fast with a descriptive message if the Claude design skill source directory (`ai/claude/skills/yasdef-worker-design/`) is missing from the YASDEF source repo.

#### Scenario: Claude design skill is installed into the target repo
- **WHEN** the operator runs `ai/scripts/init_asdlc_worker.sh` against a target repo
- **THEN** `<target-repo>/.claude/skills/yasdef-worker-design/SKILL.md` exists
- **THEN** `<target-repo>/.claude/skills/yasdef-worker-design/scripts/build_design_context.py` exists
- **THEN** `<target-repo>/.claude/skills/yasdef-worker-design/scripts/check_design_readiness.py` exists
- **THEN** `<target-repo>/.claude/skills/yasdef-worker-design/assets/feature_design_TEMPLATE.md` exists
- **THEN** `<target-repo>/.claude/skills/yasdef-worker-design/assets/feature_design_GOLDEN_EXAMPLE.md` exists

#### Scenario: Claude design slash command is installed into the target repo
- **WHEN** the operator runs `ai/scripts/init_asdlc_worker.sh` against a target repo
- **THEN** `<target-repo>/.claude/commands/yasdef/design.md` exists

#### Scenario: Codex design skill installation is unaffected
- **WHEN** the operator runs `ai/scripts/init_asdlc_worker.sh` against a target repo
- **THEN** `<target-repo>/.codex/skills/yasdef-worker-design/` is installed in full alongside the new Claude design install paths
- **THEN** the existing Claude ai_audit install paths (from CRP-133) are also installed unchanged
- **THEN** the install order of Codex skills relative to other phases is unchanged

#### Scenario: Claude design install paths are added to .git/info/exclude
- **WHEN** the operator runs `ai/scripts/init_asdlc_worker.sh` against a target repo
- **THEN** `<target-repo>/.git/info/exclude` contains the line `.claude/skills/yasdef-worker-design`

#### Scenario: Claude design install paths are tracked at HEAD after bootstrap commit
- **WHEN** the operator runs `ai/scripts/init_asdlc_worker.sh` against a target repo
- **THEN** all files under `<target-repo>/.claude/skills/yasdef-worker-design/` are tracked at HEAD in the target repo
- **THEN** `<target-repo>/.claude/commands/yasdef/design.md` is tracked at HEAD in the target repo

#### Scenario: Init fails fast if Claude design source tree is missing
- **WHEN** the operator runs `ai/scripts/init_asdlc_worker.sh` against a target repo while the YASDEF source repo is missing `ai/claude/skills/yasdef-worker-design/`
- **THEN** the init flow fails with a descriptive message naming the missing source directory
- **THEN** no partial Claude design install is left in the target repo
