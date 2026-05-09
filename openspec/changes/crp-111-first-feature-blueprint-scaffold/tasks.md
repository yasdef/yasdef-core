## 1. Add blueprint-aware bootstrap handling to design

- [ ] 1.1 Extend `ai/scripts/ai_design.sh` so the design prompt explicitly decides whether the current step is the first implementation step on an empty or near-empty repo.
- [ ] 1.2 Add `ai/scripts/helpers/helper_find_blueprints.sh` as a helper script that the design model is instructed to execute during the design phase from the ASDLC feature folder context where `implementation_plan.md` and `requirements_ears.md` live; when run there, it must search the parent project-level directory for `project_stack_blueprint_*.md`.
- [ ] 1.3 Read project class metadata from `ai/project_overmind.yaml` and use it to scope blueprint lookup to the current class (`back`, `front`, `mobile`).
- [ ] 1.4 Update `ai/scripts/ai_design.sh` so bootstrap cases explicitly instruct the design model to run `ai/scripts/helpers/helper_find_blueprints.sh` when stack/architecture guidance is needed and to record the result in canonical output sections.
- [ ] 1.5 Update `ai/templates/feature_design_TEMPLATE.md` and the design golden example with `## First-Feature Bootstrap Decision`, `## Blueprint Context`, and `## Scaffold Creation Handoff`.

## 2. Enforce unresolved bootstrap decisions at design handoff

- [ ] 2.1 Extend `ai/scripts/helpers/check_design_readiness.sh` so first-feature bootstrap design cannot pass readiness unless scaffold creation is resolved.
- [ ] 2.2 Fail readiness when bootstrap is required but no relevant blueprint was found and no explicit user decision has been captured.
- [ ] 2.3 Add/update prompt contract tests covering blueprint found, blueprint missing, irrelevant blueprint, and non-bootstrap cases.

## 3. Make planning consume scaffold handoff deterministically

- [ ] 3.1 Extend `ai/scripts/ai_plan.sh` so planning reads `## First-Feature Bootstrap Decision` and `## Scaffold Creation Handoff` from the design artifact as the source of truth for whether bootstrap is required; planning must not re-investigate or re-decide first-feature bootstrap status on its own.
- [ ] 3.2 Update `ai/templates/step_plan_TEMPLATE.md` and golden examples to add a canonical `## Scaffold Bootstrap Plan` section.
- [ ] 3.3 Require ordered plan bullets to place scaffold creation before dependent feature implementation work when bootstrap is required.
- [ ] 3.4 Extend `ai/scripts/helpers/check_planning_readiness.sh` so implementation readiness fails if first-feature bootstrap planning omitted mandatory scaffold work.

## 4. Documentation and tests

- [ ] 4.1 Update `Readme.md` and `ai/AI_DEVELOPMENT_PROCESS.md` to describe blueprint-aware first-feature bootstrap behavior in design/planning.
- [ ] 4.2 Add or update shell tests under `tests/ai_scripts/` for helper lookup, design prompt contract, planning prompt contract, and readiness gates.
- [ ] 4.3 Run the relevant `tests/ai_scripts/` suites from repo root and confirm the new contract is covered.
