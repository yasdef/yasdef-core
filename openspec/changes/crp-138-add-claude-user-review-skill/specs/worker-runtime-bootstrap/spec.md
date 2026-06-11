## ADDED Requirements

### Requirement: Worker init installs the Claude user_review skill and slash command

The worker init flow (`ai/scripts/init_asdlc_worker.sh`) SHALL install the Claude Code user_review skill at `<target-repo>/.claude/skills/yasdef-worker-user-review/` and the Claude Code slash command at `<target-repo>/.claude/commands/yasdef/user-review.md` during the same bootstrap pass that installs the Codex skill set under `<target-repo>/.codex/skills/` and the Claude ai_audit/design/plan/implementation skill sets introduced by CRP-133 / CRP-135 / CRP-136 / CRP-137.

The Claude user_review skill install path SHALL be registered in the init flow's generated-exclude list (so it is added to `<target-repo>/.git/info/exclude`) and the durable-commit list (so it is tracked at HEAD after the bootstrap commit). The new slash command file path `.claude/commands/yasdef/user-review.md` SHALL be added to the durable-commit list; the `.claude/commands/yasdef` directory exclude entry from CRP-133 already covers it.

The init flow SHALL fail fast with a descriptive message if the Claude user_review skill source directory (`ai/claude/skills/yasdef-worker-user-review/`) is missing from the YASDEF source repo.

After this change ships, the worker init flow SHALL install a full set of five Claude phase skills (`yasdef-worker-design`, `yasdef-worker-plan`, `yasdef-worker-implementation`, `yasdef-worker-user-review`, `yasdef-worker-ai-audit`) and five Claude slash commands (`design.md`, `plan.md`, `implementation.md`, `user-review.md`, `audit.md`) into target repos, parity with the existing Codex skill set.

#### Scenario: Claude user_review skill is installed into the target repo
- **WHEN** the operator runs `ai/scripts/init_asdlc_worker.sh` against a target repo
- **THEN** `<target-repo>/.claude/skills/yasdef-worker-user-review/SKILL.md` exists
- **THEN** `<target-repo>/.claude/skills/yasdef-worker-user-review/scripts/build_user_review_context.py` exists
- **THEN** `<target-repo>/.claude/skills/yasdef-worker-user-review/assets/review_brief_TEMPLATE.md` exists
- **THEN** `<target-repo>/.claude/skills/yasdef-worker-user-review/assets/review_brief_GOLDEN_EXAMPLE.md` exists
- **THEN** `<target-repo>/.claude/skills/yasdef-worker-user-review/assets/user_review_TEMPLATE.md` exists
- **THEN** `<target-repo>/.claude/skills/yasdef-worker-user-review/assets/user_review_GOLDEN_EXAMPLE.md` exists

#### Scenario: Claude user_review slash command is installed into the target repo
- **WHEN** the operator runs `ai/scripts/init_asdlc_worker.sh` against a target repo
- **THEN** `<target-repo>/.claude/commands/yasdef/user-review.md` exists

#### Scenario: Full Claude phase parity after bootstrap
- **WHEN** the operator runs `ai/scripts/init_asdlc_worker.sh` against a target repo
- **THEN** all five Claude skill directories exist under `<target-repo>/.claude/skills/`: `yasdef-worker-design`, `yasdef-worker-plan`, `yasdef-worker-implementation`, `yasdef-worker-user-review`, `yasdef-worker-ai-audit`
- **THEN** all five Claude slash command files exist under `<target-repo>/.claude/commands/yasdef/`: `design.md`, `plan.md`, `implementation.md`, `user-review.md`, `audit.md`

#### Scenario: Codex user_review skill installation is unaffected
- **WHEN** the operator runs `ai/scripts/init_asdlc_worker.sh` against a target repo
- **THEN** `<target-repo>/.codex/skills/yasdef-worker-user-review/` is installed in full alongside the new Claude user_review install paths
- **THEN** the existing Claude ai_audit / design / plan / implementation install paths (from CRP-133 / CRP-135 / CRP-136 / CRP-137) are also installed unchanged
- **THEN** the install order of Codex skills relative to other phases is unchanged

#### Scenario: Claude user_review install paths are added to .git/info/exclude
- **WHEN** the operator runs `ai/scripts/init_asdlc_worker.sh` against a target repo
- **THEN** `<target-repo>/.git/info/exclude` contains the line `.claude/skills/yasdef-worker-user-review`

#### Scenario: Claude user_review install paths are tracked at HEAD after bootstrap commit
- **WHEN** the operator runs `ai/scripts/init_asdlc_worker.sh` against a target repo
- **THEN** all files under `<target-repo>/.claude/skills/yasdef-worker-user-review/` are tracked at HEAD in the target repo
- **THEN** `<target-repo>/.claude/commands/yasdef/user-review.md` is tracked at HEAD in the target repo

#### Scenario: Init fails fast if Claude user_review source tree is missing
- **WHEN** the operator runs `ai/scripts/init_asdlc_worker.sh` against a target repo while the YASDEF source repo is missing `ai/claude/skills/yasdef-worker-user-review/`
- **THEN** the init flow fails with a descriptive message naming the missing source directory
- **THEN** no partial Claude user_review install is left in the target repo
