## Why

The design phase currently depends on a generated one-shot prompt and shell-only parsing, which makes design work less interactive and leaves too much design-specific behavior in the orchestrator/runtime scripts. Moving design into a Codex skill keeps the phase interactive while preserving shell orchestration and scoped artifacts.

## What Changes

- Add a project-provided Codex skill at `ai/codex/skills/yasdef-worker-design` for ASDLC worker design sessions.
- Move the design template and golden example into the design skill assets so design output shape is owned by the skill.
- Install/update that skill into target projects at `.codex/skills/yasdef-worker-design` during worker initialization.
- Remove legacy design prompt helpers (`ai_design.sh` and shell `check_design_readiness.sh`) from the source/runtime path.
- Change the orchestrator design phase to invoke the model with a compact prompt that calls the `yasdef-worker-design` skill instead of generating a full design prompt via `ai_design.sh`.
- Replace the detailed design block in `ai/AI_DEVELOPMENT_PROCESS.md` with a reference to the installed skill.
- Add repository tests for the skill Python scripts under `tests/skills_python_scripts`.

## Capabilities

### New Capabilities
- `yasdef-worker-design-skill`: Defines the repo-provided Codex skill that owns ASDLC worker design-phase context assembly, interaction rules, artifact initialization, and readiness validation.

### Modified Capabilities
- `worker-runtime-bootstrap`: Installs the design skill into `.codex/skills` and excludes legacy design shell helpers from runtime installation/update.
- `orchestrator-worker-assigned-step-routing`: Routes the design phase through a skill-invoking Codex prompt while preserving existing feature/step selection and downstream phases.
- `design-to-planning-readiness-gate`: Moves design readiness validation ownership from installed shell helper to the skill-bundled Python gate.

## Impact

- `ai/codex/skills/yasdef-worker-design/**`: new skill definition, Python scripts, and design template/golden-example assets.
- `ai/templates/feature_design_TEMPLATE.md` and `ai/golden_examples/feature_design_GOLDEN_EXAMPLE.md`: removed; the design skill owns these assets now.
- `ai/scripts/init_asdlc_worker.sh`: copies the skill into target `.codex/skills` and ignores generated skill files.
- `ai/scripts/orchestrator.sh`: no longer requires or runs `ai_design.sh`; design phase invokes the configured model with a skill call prompt.
- `ai/AI_DEVELOPMENT_PROCESS.md`: section 1 becomes a pointer to the installed skill.
- `tests/skills_python_scripts/**` and selected script tests: cover skill scripts and install/routing behavior.
