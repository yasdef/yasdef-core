## ADDED Requirements

### Requirement: Claude Code skill source tree mirrors the Codex user_review skill

The repository SHALL provide a Claude Code skill source tree at `ai/claude/skills/yasdef-worker-user-review/` that is functionally identical to the Codex skill at `ai/codex/skills/yasdef-worker-user-review/`.

The Claude skill source tree SHALL contain:
- a `SKILL.md` file defining the same 6 inputs (step id, feature id, branch, step plan path, design artifact path, runtime implementation plan path), the same executing-phase semantics (this phase edits runtime code in response to user feedback), the same durable-rules update behavior on `.asdlc_worker/user_review.md`, the same review-brief authoring shape, and the same exact sentinel completion line as the Codex skill;
- a `scripts/` subdirectory containing `build_user_review_context.py` byte-identical to its Codex counterpart;
- an `assets/` subdirectory containing `review_brief_TEMPLATE.md`, `review_brief_GOLDEN_EXAMPLE.md`, `user_review_TEMPLATE.md`, and `user_review_GOLDEN_EXAMPLE.md` byte-identical to their Codex counterparts.

The Claude `SKILL.md` MAY differ from the Codex `SKILL.md` in framing, frontmatter shape, asset-reference syntax, or other structural elements where Claude Code skill conventions differ from Codex, but MUST NOT change the workflow contract or input/output semantics.

#### Scenario: Python helper drift between Codex and Claude trees is rejected
- **WHEN** any file under `ai/claude/skills/yasdef-worker-user-review/scripts/` differs from the corresponding file under `ai/codex/skills/yasdef-worker-user-review/scripts/`
- **THEN** the divergence is treated as a bug and SHALL be reconciled before the change ships

#### Scenario: Asset drift between Codex and Claude trees is rejected
- **WHEN** any file under `ai/claude/skills/yasdef-worker-user-review/assets/` differs from the corresponding file under `ai/codex/skills/yasdef-worker-user-review/assets/`
- **THEN** the divergence is treated as a bug and SHALL be reconciled before the change ships

#### Scenario: Claude SKILL.md may diverge to match Claude Code conventions
- **WHEN** Claude Code skill convention differs from Codex skill convention in a way that affects only framing, frontmatter, or in-skill cross-references
- **THEN** the Claude `SKILL.md` MAY be authored to match Claude convention even if it differs textually from the Codex `SKILL.md`, provided the 6 inputs, the durable-rules update behavior, the review-brief authoring shape, and the exact sentinel completion line are preserved

### Requirement: Claude Code slash command exposes the user_review skill with explicit inputs

The repository SHALL provide a Claude Code slash command at `ai/claude/commands/yasdef/user-review.md` (named with a hyphen to match the skill directory naming convention) that invokes the `yasdef-worker-user-review` skill with all six inputs supplied explicitly by the caller: step id, feature id, branch, step plan path, design artifact path, and runtime implementation plan path.

The slash command body SHALL NOT read `.asdlc_worker/feature_meta_sync.yaml` and SHALL NOT infer any of the six inputs from runtime context. If the caller omits any input, the command body SHALL instruct the model to stop and ask the user for the missing input rather than infer it.

The slash command prompt body SHALL mirror the shape produced by `run_user_review_phase` in `ai/scripts/orchestrator.sh`, listing the six inputs as labeled lines under an `Inputs:` block.

#### Scenario: Slash command passes all six inputs to the skill
- **WHEN** the operator invokes the `/yasdef:user-review` slash command with the six required inputs
- **THEN** the command body produces a model prompt that invokes the `yasdef-worker-user-review` skill with the six inputs labeled as `Step`, `Feature id`, `Branch`, `Step plan`, `Design artifact`, `Runtime implementation plan`

#### Scenario: Slash command does not introspect feature_meta_sync.yaml
- **WHEN** the operator invokes the `/yasdef:user-review` slash command and one or more inputs are missing
- **THEN** the command body does NOT read `.asdlc_worker/feature_meta_sync.yaml` to fill in the missing inputs
- **THEN** the command body instructs the model to stop and ask the user for the missing inputs
