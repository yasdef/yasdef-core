## ADDED Requirements

### Requirement: Claude Code skill source tree mirrors the Codex ai_audit skill

The repository SHALL provide a Claude Code skill source tree at `ai/claude/skills/yasdef-worker-ai-audit/` that is functionally identical to the Codex skill at `ai/codex/skills/yasdef-worker-ai-audit/`.

The Claude skill source tree SHALL contain:
- a `SKILL.md` file defining the same 7 inputs, 9-step workflow, six closure error categories, analysis-only / commit-boundary / read-target rules, and the same exact sentinel completion line as the Codex skill;
- a `scripts/` subdirectory containing `check_ai_audit_entry.py`, `build_ai_audit_context.py`, and `check_ai_audit_closure.py` byte-identical to their Codex counterparts;
- an `assets/` subdirectory containing `audit_result_TEMPLATE.md`, `audit_result_GOLDEN_EXAMPLE.md`, `raised_question_TEMPLATE.md`, and `raised_question_GOLDEN_EXAMPLE.md` byte-identical to their Codex counterparts.

The Claude `SKILL.md` MAY differ from the Codex `SKILL.md` in framing, frontmatter shape, asset-reference syntax, or other structural elements where Claude Code skill conventions differ from Codex, but MUST NOT change the workflow contract or input/output semantics.

#### Scenario: Python helper drift between Codex and Claude trees is rejected
- **WHEN** any file under `ai/claude/skills/yasdef-worker-ai-audit/scripts/` differs from the corresponding file under `ai/codex/skills/yasdef-worker-ai-audit/scripts/`
- **THEN** the divergence is treated as a bug and SHALL be reconciled before the change ships

#### Scenario: Asset drift between Codex and Claude trees is rejected
- **WHEN** any file under `ai/claude/skills/yasdef-worker-ai-audit/assets/` differs from the corresponding file under `ai/codex/skills/yasdef-worker-ai-audit/assets/`
- **THEN** the divergence is treated as a bug and SHALL be reconciled before the change ships

#### Scenario: Claude SKILL.md may diverge to match Claude Code conventions
- **WHEN** Claude Code skill convention differs from Codex skill convention in a way that affects only framing, frontmatter, or in-skill cross-references
- **THEN** the Claude `SKILL.md` MAY be authored to match Claude convention even if it differs textually from the Codex `SKILL.md`, provided the 7 inputs, the 9 workflow steps, the 6 closure error categories, and the exact sentinel completion line are preserved

### Requirement: Claude Code slash command exposes the ai_audit skill with explicit inputs

The repository SHALL provide a Claude Code slash command at `ai/claude/commands/yasdef/audit.md` that invokes the `yasdef-worker-ai-audit` skill with all seven inputs supplied explicitly by the caller: step id, feature id, branch, step plan path, design artifact path, runtime implementation plan path, and worker id.

The slash command body SHALL NOT read `.asdlc_worker/feature_meta_sync.yaml` and SHALL NOT infer any of the seven inputs from runtime context. If the caller omits any input, the command body SHALL instruct the model to stop and ask the user for the missing input rather than infer it.

The slash command prompt body SHALL mirror the shape produced by the orchestrator's `write_ai_audit_skill_prompt`, listing the seven inputs as labeled lines under an `Inputs:` block.

#### Scenario: Slash command passes all seven inputs to the skill
- **WHEN** the operator invokes the `/yasdef:audit` slash command with the seven required inputs
- **THEN** the command body produces a model prompt that invokes the `yasdef-worker-ai-audit` skill with the seven inputs labeled as `Step`, `Feature id`, `Branch`, `Step plan`, `Design artifact`, `Runtime implementation plan`, `Worker id`

#### Scenario: Slash command does not introspect feature_meta_sync.yaml
- **WHEN** the operator invokes the `/yasdef:audit` slash command and one or more inputs are missing
- **THEN** the command body does NOT read `.asdlc_worker/feature_meta_sync.yaml` to fill in the missing inputs
- **THEN** the command body instructs the model to stop and ask the user for the missing inputs
