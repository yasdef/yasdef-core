## Why

The first implementation step on an empty or near-empty repo is structurally different from normal feature work: it often needs scaffold creation and an explicit stack/architecture choice before detailed implementation planning is useful. Today the design/planning flow can miss existing ASDLC project blueprints that live at the project level while `implementation_plan.md` and `requirements_ears.md` live at feature level, which leads to ad-hoc stack choices, inconsistent scaffolds, or planning artifacts that assume a scaffold exists when it does not.

## What Changes

- Teach the design phase to make an explicit first-feature bootstrap decision for the current step: normal feature work vs. first implementation on an empty or near-empty repo.
- When design identifies first-feature bootstrap and stack/architecture guidance is needed, require it to run `ai/scripts/helpers/helper_find_blueprints.sh` from the ASDLC feature source context where feature-level `implementation_plan.md` and `requirements_ears.md` live, and make the helper check the parent project-level directory for blueprints.
- Use project class metadata from `ai/project_overmind.yaml` to scope blueprint lookup to the current class (`back`, `front`, or `mobile`).
- If a relevant `project_stack_blueprint_*.md` file exists and is suitable for scaffold creation, require design output to include blueprint-backed scaffold handoff data that planning can consume.
- If no relevant blueprint exists, or if found blueprints are not suitable, require design to stop and ask the user to decide the tech stack instead of inventing one.
- When the step is the first feature implementation on an empty repo, require planning to always include scaffold creation as mandatory work and to use the scaffold handoff data from design when preparing the implementation plan.

## Capabilities

### New Capabilities
- `first-feature-blueprint-scaffold-handoff`: Design detects first-feature bootstrap, resolves class-scoped stack blueprints from the ASDLC project level above the current feature artifact folder, and passes scaffold creation data into planning.

### Modified Capabilities
- `design-to-planning-readiness-gate`: design is not handoff-ready for first-feature bootstrap until scaffold creation is resolved either through a valid blueprint-backed handoff or an explicit user stack decision.
- `planning-to-implementation-readiness-gate`: planning is not implementation-ready for first-feature bootstrap unless scaffold creation is present as mandatory plan work derived from the design handoff.

## Impact

- Prompt contracts:
  - `ai/scripts/ai_design.sh`
  - `ai/scripts/ai_plan.sh`
- Helpers:
  - new `ai/scripts/helpers/helper_find_blueprints.sh`
  - existing readiness helpers for design/planning may need conditional first-feature checks
- Templates and examples:
  - `ai/templates/feature_design_TEMPLATE.md`
  - `ai/templates/step_plan_TEMPLATE.md`
  - related golden examples
- Documentation:
  - `Readme.md`
  - `ai/AI_DEVELOPMENT_PROCESS.md` where design/planning boundary behavior is described
- Tests:
  - targeted shell tests for design prompt contract, planning prompt contract, and readiness gates
