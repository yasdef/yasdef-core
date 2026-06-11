## MODIFIED Requirements

### Requirement: Worker runtime initialization installs generated runtime assets
The worker runtime initializer MUST install generated ASDLC worker assets into the target repository, and it MUST also install the YASDEF design Codex skill into `.codex/skills/yasdef-worker-design` without installing legacy design shell helpers.

#### Scenario: Design skill is installed into target project
- **WHEN** `ai/scripts/init_asdlc_worker.sh` initializes or updates a target repository
- **THEN** the target contains `.codex/skills/yasdef-worker-design/SKILL.md`
- **AND** the target contains the skill Python scripts under `.codex/skills/yasdef-worker-design/scripts/`
- **AND** the target contains the skill design assets under `.codex/skills/yasdef-worker-design/assets/`
- **AND** `.git/info/exclude` does not contain `.codex/skills/yasdef-worker-design`

#### Scenario: Design skill is tracked by the target project
- **WHEN** `ai/scripts/init_asdlc_worker.sh` initializes a target repository
- **THEN** `.codex/skills/yasdef-worker-design/SKILL.md` is tracked in the target repository HEAD
- **AND** the design skill scripts and assets are tracked in the target repository HEAD

#### Scenario: Legacy design shell helpers are absent
- **WHEN** `ai/scripts/init_asdlc_worker.sh` initializes or updates a target repository
- **THEN** `.asdlc_worker/scripts/ai_design.sh` is absent
- **AND** `.asdlc_worker/scripts/helpers/check_design_readiness.sh` is absent

#### Scenario: Installed design skill survives first-install cleanup
- **WHEN** worker initialization stashes unrelated target worktree changes after the durable runtime commit
- **THEN** `.codex/skills/yasdef-worker-design` remains present in the target worktree
