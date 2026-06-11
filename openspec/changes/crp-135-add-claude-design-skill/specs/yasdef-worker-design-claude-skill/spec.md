## ADDED Requirements

### Requirement: Claude Code skill source tree mirrors the Codex design skill

The repository SHALL provide a Claude Code skill source tree at `ai/claude/skills/yasdef-worker-design/` that is functionally identical to the Codex skill at `ai/codex/skills/yasdef-worker-design/`.

The Claude skill source tree SHALL contain:
- a `SKILL.md` file defining the same 5 inputs (step id, feature id, branch, design output path, runtime implementation plan path, runtime requirements EARS path), the same analysis-only / no-runtime-code rule, the same workflow, the same closure / readiness invariants, and the same exact sentinel completion line as the Codex skill;
- a `scripts/` subdirectory containing `build_design_context.py` and `check_design_readiness.py` byte-identical to their Codex counterparts;
- an `assets/` subdirectory containing `feature_design_TEMPLATE.md` and `feature_design_GOLDEN_EXAMPLE.md` byte-identical to their Codex counterparts.

The Claude `SKILL.md` MAY differ from the Codex `SKILL.md` in framing, frontmatter shape, asset-reference syntax, or other structural elements where Claude Code skill conventions differ from Codex, but MUST NOT change the workflow contract or input/output semantics.

#### Scenario: Python helper drift between Codex and Claude trees is rejected
- **WHEN** any file under `ai/claude/skills/yasdef-worker-design/scripts/` differs from the corresponding file under `ai/codex/skills/yasdef-worker-design/scripts/`
- **THEN** the divergence is treated as a bug and SHALL be reconciled before the change ships

#### Scenario: Asset drift between Codex and Claude trees is rejected
- **WHEN** any file under `ai/claude/skills/yasdef-worker-design/assets/` differs from the corresponding file under `ai/codex/skills/yasdef-worker-design/assets/`
- **THEN** the divergence is treated as a bug and SHALL be reconciled before the change ships

#### Scenario: Claude SKILL.md may diverge to match Claude Code conventions
- **WHEN** Claude Code skill convention differs from Codex skill convention in a way that affects only framing, frontmatter, or in-skill cross-references
- **THEN** the Claude `SKILL.md` MAY be authored to match Claude convention even if it differs textually from the Codex `SKILL.md`, provided the 5 inputs, the workflow, and the exact sentinel completion line are preserved

### Requirement: Claude Code slash command exposes the design skill with explicit inputs

The repository SHALL provide a Claude Code slash command at `ai/claude/commands/yasdef/design.md` that invokes the `yasdef-worker-design` skill with all five inputs supplied explicitly by the caller: step id, feature id, branch, design output path, runtime implementation plan path, and runtime requirements EARS path.

The slash command body SHALL NOT read `.asdlc_worker/feature_meta_sync.yaml` and SHALL NOT infer any of the five inputs from runtime context. If the caller omits any input, the command body SHALL instruct the model to stop and ask the user for the missing input rather than infer it.

The slash command prompt body SHALL mirror the shape produced by `run_design_phase` in `ai/scripts/orchestrator.sh`, listing the five inputs as labeled lines under an `Inputs:` block.

#### Scenario: Slash command passes all five inputs to the skill
- **WHEN** the operator invokes the `/yasdef:design` slash command with the five required inputs
- **THEN** the command body produces a model prompt that invokes the `yasdef-worker-design` skill with the five inputs labeled as `Step`, `Feature id`, `Branch`, `Design output`, `Runtime implementation plan`, `Runtime requirements EARS`

#### Scenario: Slash command does not introspect feature_meta_sync.yaml
- **WHEN** the operator invokes the `/yasdef:design` slash command and one or more inputs are missing
- **THEN** the command body does NOT read `.asdlc_worker/feature_meta_sync.yaml` to fill in the missing inputs
- **THEN** the command body instructs the model to stop and ask the user for the missing inputs
