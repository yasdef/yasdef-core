## ADDED Requirements

### Requirement: Claude Code skill source tree mirrors the Codex planning skill

The repository SHALL provide a Claude Code skill source tree at `ai/claude/skills/yasdef-worker-plan/` that is functionally identical to the Codex skill at `ai/codex/skills/yasdef-worker-plan/`.

The Claude skill source tree SHALL contain:
- a `SKILL.md` file defining the same 8 inputs (step id, feature id, branch, design artifact path, step plan output path, runtime implementation plan path, open-questions ledger path, blockers ledger path), the same iteration workflow, the same readiness invariants enforced by `check_planning_readiness.py`, the same LARS-sync responsibilities of `sync_step_lars.py`, the same analysis-only / no-runtime-code rule, and the same exact sentinel completion line as the Codex skill;
- a `scripts/` subdirectory containing `build_plan_context.py`, `check_planning_readiness.py`, and `sync_step_lars.py` byte-identical to their Codex counterparts;
- an `assets/` subdirectory containing `step_plan_TEMPLATE.md` and `step_plan_GOLDEN_EXAMPLE.md` byte-identical to their Codex counterparts.

The Claude `SKILL.md` MAY differ from the Codex `SKILL.md` in framing, frontmatter shape, asset-reference syntax, or other structural elements where Claude Code skill conventions differ from Codex, but MUST NOT change the workflow contract or input/output semantics.

#### Scenario: Python helper drift between Codex and Claude trees is rejected
- **WHEN** any file under `ai/claude/skills/yasdef-worker-plan/scripts/` differs from the corresponding file under `ai/codex/skills/yasdef-worker-plan/scripts/`
- **THEN** the divergence is treated as a bug and SHALL be reconciled before the change ships

#### Scenario: Asset drift between Codex and Claude trees is rejected
- **WHEN** any file under `ai/claude/skills/yasdef-worker-plan/assets/` differs from the corresponding file under `ai/codex/skills/yasdef-worker-plan/assets/`
- **THEN** the divergence is treated as a bug and SHALL be reconciled before the change ships

#### Scenario: Claude SKILL.md may diverge to match Claude Code conventions
- **WHEN** Claude Code skill convention differs from Codex skill convention in a way that affects only framing, frontmatter, or in-skill cross-references
- **THEN** the Claude `SKILL.md` MAY be authored to match Claude convention even if it differs textually from the Codex `SKILL.md`, provided the 8 inputs, the iteration workflow, and the exact sentinel completion line are preserved

### Requirement: Claude Code slash command exposes the planning skill with explicit inputs

The repository SHALL provide a Claude Code slash command at `ai/claude/commands/yasdef/plan.md` that invokes the `yasdef-worker-plan` skill with all eight inputs supplied explicitly by the caller: step id, feature id, branch, design artifact path, step plan output path, runtime implementation plan path, open-questions ledger path, and blockers ledger path.

The slash command body SHALL NOT read `.asdlc_worker/feature_meta_sync.yaml` and SHALL NOT infer any of the eight inputs from runtime context. If the caller omits any input, the command body SHALL instruct the model to stop and ask the user for the missing input rather than infer it.

The slash command prompt body SHALL mirror the shape produced by `run_planning_phase` in `ai/scripts/orchestrator.sh`, listing the eight inputs as labeled lines under an `Inputs:` block.

#### Scenario: Slash command passes all eight inputs to the skill
- **WHEN** the operator invokes the `/yasdef:plan` slash command with the eight required inputs
- **THEN** the command body produces a model prompt that invokes the `yasdef-worker-plan` skill with the eight inputs labeled as `Step`, `Feature id`, `Branch`, `Design artifact`, `Step plan output`, `Runtime implementation plan`, `Open questions ledger`, `Blockers ledger`

#### Scenario: Slash command does not introspect feature_meta_sync.yaml
- **WHEN** the operator invokes the `/yasdef:plan` slash command and one or more inputs are missing
- **THEN** the command body does NOT read `.asdlc_worker/feature_meta_sync.yaml` to fill in the missing inputs
- **THEN** the command body instructs the model to stop and ask the user for the missing inputs
