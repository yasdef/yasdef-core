## ADDED Requirements

### Requirement: Claude Code skill source tree mirrors the Codex implementation skill

The repository SHALL provide a Claude Code skill source tree at `ai/claude/skills/yasdef-worker-implementation/` that is functionally identical to the Codex skill at `ai/codex/skills/yasdef-worker-implementation/`.

The Claude skill source tree SHALL contain:
- a `SKILL.md` file defining the same 6 inputs (step id, feature id, branch, step plan path, design artifact path, runtime implementation plan path), the same executing-phase semantics (this is the only phase that edits runtime code), the same step-plan checklist update behavior, the same readiness invariants enforced by `check_implementation_readiness.py`, and the same exact sentinel completion line as the Codex skill;
- a `scripts/` subdirectory containing `build_implementation_context.py` and `check_implementation_readiness.py` byte-identical to their Codex counterparts.

The Claude skill source tree SHALL NOT contain an `assets/` subdirectory, in parity with the Codex skill source tree.

The Claude `SKILL.md` MAY differ from the Codex `SKILL.md` in framing, frontmatter shape, asset-reference syntax, or other structural elements where Claude Code skill conventions differ from Codex, but MUST NOT change the workflow contract or input/output semantics.

#### Scenario: Python helper drift between Codex and Claude trees is rejected
- **WHEN** any file under `ai/claude/skills/yasdef-worker-implementation/scripts/` differs from the corresponding file under `ai/codex/skills/yasdef-worker-implementation/scripts/`
- **THEN** the divergence is treated as a bug and SHALL be reconciled before the change ships

#### Scenario: Assets parity with Codex
- **WHEN** the Codex skill source tree has no `assets/` subdirectory
- **THEN** the Claude skill source tree SHALL also have no `assets/` subdirectory
- **THEN** if a future change introduces `assets/` to the Codex tree, the Claude tree MUST be updated in the same change to mirror it

#### Scenario: Claude SKILL.md may diverge to match Claude Code conventions
- **WHEN** Claude Code skill convention differs from Codex skill convention in a way that affects only framing, frontmatter, or in-skill cross-references
- **THEN** the Claude `SKILL.md` MAY be authored to match Claude convention even if it differs textually from the Codex `SKILL.md`, provided the 6 inputs, the workflow, and the exact sentinel completion line are preserved

### Requirement: Claude Code slash command exposes the implementation skill with explicit inputs

The repository SHALL provide a Claude Code slash command at `ai/claude/commands/yasdef/implementation.md` that invokes the `yasdef-worker-implementation` skill with all six inputs supplied explicitly by the caller: step id, feature id, branch, step plan path, design artifact path, and runtime implementation plan path.

The slash command body SHALL NOT read `.asdlc_worker/feature_meta_sync.yaml` and SHALL NOT infer any of the six inputs from runtime context. If the caller omits any input, the command body SHALL instruct the model to stop and ask the user for the missing input rather than infer it.

The slash command prompt body SHALL mirror the shape produced by `run_implementation_phase` in `ai/scripts/orchestrator.sh`, listing the six inputs as labeled lines under an `Inputs:` block.

#### Scenario: Slash command passes all six inputs to the skill
- **WHEN** the operator invokes the `/yasdef:implementation` slash command with the six required inputs
- **THEN** the command body produces a model prompt that invokes the `yasdef-worker-implementation` skill with the six inputs labeled as `Step`, `Feature id`, `Branch`, `Step plan`, `Design artifact`, `Runtime implementation plan`

#### Scenario: Slash command does not introspect feature_meta_sync.yaml
- **WHEN** the operator invokes the `/yasdef:implementation` slash command and one or more inputs are missing
- **THEN** the command body does NOT read `.asdlc_worker/feature_meta_sync.yaml` to fill in the missing inputs
- **THEN** the command body instructs the model to stop and ask the user for the missing inputs
