## MODIFIED Requirements

### Requirement: Worker init installs Codex and Claude ai_audit skills plus the Claude slash command

The worker init flow (`ai/scripts/init_asdlc_worker.sh`) SHALL install the Claude Code ai_audit skill at `<target-repo>/.claude/skills/yasdef-worker-ai-audit/` and the Claude Code slash command at `<target-repo>/.claude/commands/yasdef/audit.md` during the same bootstrap pass that installs the Codex skill set under `<target-repo>/.codex/skills/`.

Both new install paths SHALL be registered in the init flow's generated-exclude list (so they are added to `<target-repo>/.git/info/exclude`) and the durable-commit list (so they are tracked at HEAD after the bootstrap commit).

The init flow SHALL fail fast with a descriptive message if either the Claude skill source directory (`ai/claude/skills/yasdef-worker-ai-audit/`) or the Claude commands source directory (`ai/claude/commands/yasdef/`) is missing from the YASDEF source repo.

#### Scenario: Claude skill is installed into the target repo
- **WHEN** the operator runs `ai/scripts/init_asdlc_worker.sh` against a target repo
- **THEN** `<target-repo>/.claude/skills/yasdef-worker-ai-audit/SKILL.md` exists
- **THEN** `<target-repo>/.claude/skills/yasdef-worker-ai-audit/scripts/check_ai_audit_entry.py` exists
- **THEN** `<target-repo>/.claude/skills/yasdef-worker-ai-audit/scripts/build_ai_audit_context.py` exists
- **THEN** `<target-repo>/.claude/skills/yasdef-worker-ai-audit/scripts/check_ai_audit_closure.py` exists
- **THEN** all four asset files under `<target-repo>/.claude/skills/yasdef-worker-ai-audit/assets/` exist

#### Scenario: Claude slash command is installed into the target repo
- **WHEN** the operator runs `ai/scripts/init_asdlc_worker.sh` against a target repo
- **THEN** `<target-repo>/.claude/commands/yasdef/audit.md` exists

#### Scenario: Codex skill installation is unaffected
- **WHEN** the operator runs `ai/scripts/init_asdlc_worker.sh` against a target repo
- **THEN** `<target-repo>/.codex/skills/yasdef-worker-ai-audit/` is installed in full alongside the new Claude install paths
- **THEN** the install order of Codex skills relative to other phases is unchanged

#### Scenario: Claude install paths are added to .git/info/exclude
- **WHEN** the operator runs `ai/scripts/init_asdlc_worker.sh` against a target repo
- **THEN** `<target-repo>/.git/info/exclude` contains the line `.claude/skills/yasdef-worker-ai-audit`
- **THEN** `<target-repo>/.git/info/exclude` contains the line `.claude/commands/yasdef`

#### Scenario: Claude install paths are tracked at HEAD after bootstrap commit
- **WHEN** the operator runs `ai/scripts/init_asdlc_worker.sh` against a target repo
- **THEN** all files under `<target-repo>/.claude/skills/yasdef-worker-ai-audit/` are tracked at HEAD in the target repo
- **THEN** `<target-repo>/.claude/commands/yasdef/audit.md` is tracked at HEAD in the target repo

#### Scenario: Init fails fast if Claude source tree is missing
- **WHEN** the operator runs `ai/scripts/init_asdlc_worker.sh` against a target repo while the YASDEF source repo is missing `ai/claude/skills/yasdef-worker-ai-audit/` or `ai/claude/commands/yasdef/`
- **THEN** the init flow fails with a descriptive message naming the missing source directory
- **THEN** no partial Claude install is left in the target repo
