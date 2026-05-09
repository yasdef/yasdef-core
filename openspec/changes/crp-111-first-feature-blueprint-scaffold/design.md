## Context

The current design/planning workflow is optimized for steps that extend an already-shaped codebase. That breaks down on the first real feature step in an empty or near-empty repo, where the most important decision is often whether the step must first establish project scaffold and stack boundaries before normal feature implementation can begin.

The user wants this behavior anchored to ASDLC project blueprints that may already exist at project level as `project_stack_blueprint_*.md` files. The current design/planning source context is the feature folder that contains feature-level `implementation_plan.md` and `requirements_ears.md`, so blueprint lookup should happen one level up from that feature folder into the project-level directory. Project class (`back`, `front`, `mobile`) should come from `ai/project_overmind.yaml`, and the design model itself should use that class to decide whether blueprint lookup is needed and which blueprint candidates are relevant.

## Goals / Non-Goals

**Goals:**
- Force design to make an explicit yes/no decision about whether the current step is the first implementation step on an empty or near-empty repo.
- If bootstrap is needed, resolve project-level stack blueprints from the parent of the current feature artifact folder through a dedicated helper instead of relying on free-form model memory.
- Make blueprint use load-bearing: if a valid blueprint exists, design must surface scaffold creation data in a canonical section that planning can consume.
- Prevent silent stack invention: if blueprint lookup fails or produces irrelevant output, stop and ask the user to decide what stack/scaffold to use.
- Ensure planning always carries scaffold creation as mandatory work for first-feature bootstrap on an empty repo.

**Non-Goals:**
- No new CLI flags or mode toggles.
- No change to blueprint storage naming beyond consuming `project_stack_blueprint_*.md` if present.
- No attempt to implement scaffold generation itself in design; design only decides and records the scaffold handoff.
- No change to normal non-bootstrap feature planning beyond adding explicit "not a bootstrap step" handling.

## Decisions

### Decision 1: Introduce canonical design sections for bootstrap resolution

The design artifact should gain explicit sections for first-feature bootstrap handling:
- `## First-Feature Bootstrap Decision`
- `## Blueprint Context`
- `## Scaffold Creation Handoff`

Rationale: the current design artifact has no canonical place to express whether scaffold creation is required or what blueprint justified it. Planning should not parse this from prose.

### Decision 2: Treat the ASDLC project-level directory above the feature artifact folder as the blueprint search root

For a current ASDLC feature path `<project-level>/<feature-id>/` where `implementation_plan.md` and `requirements_ears.md` live at feature level, design should search for `project_stack_blueprint_*.md` at `<project-level>/`, which is one level up from the feature folder. The search itself should be delegated to `ai/scripts/helpers/helper_find_blueprints.sh`.

Rationale: this matches the user's storage model and keeps blueprint ownership at project scope while feature execution artifacts remain feature-scoped.

### Decision 3: Use bound project class from `ai/project_overmind.yaml`

Blueprint lookup should be filtered by the bound class from `ai/project_overmind.yaml` so that backend, frontend, and mobile steps do not cross-pollinate blueprint choices.

Rationale: class-scoped lookup is more reliable than guessing from repo contents, especially on near-empty repos.

Alternative considered: infer class from file layout. Rejected because empty/near-empty repos often do not have enough structure to infer safely.

### Decision 4: Design must explicitly classify bootstrap vs. non-bootstrap

The design phase should always emit one of two outcomes:
- `Bootstrap required: yes`
- `Bootstrap required: no`

This decision should include a short rationale based on repo state and the step goal. For `yes`, design must also state whether scaffold creation is required in the current step handoff.

Rationale: the user asked for the model to decide explicitly instead of leaving the bootstrap need implicit.

### Decision 5: Missing or weak blueprint evidence should force a user stop

If the step is a first-feature bootstrap case and the helper finds no relevant blueprint, or only finds files that are not clearly usable for scaffold creation for the current class, the design phase must stop and ask the user how to proceed with tech-stack selection. It must not finish the phase normally.

Rationale: stack choice is architectural and high-impact. Silent invention here would make planning look deterministic while hiding a major unresolved decision.

### Decision 6: Planning must consume scaffold handoff as mandatory plan input

When design marks first-feature bootstrap and provides scaffold handoff data, planning must copy that forward into a canonical plan section such as:
- `## Scaffold Bootstrap Plan`

The ordered plan must include scaffold creation before downstream feature tasks that depend on the scaffold.
Planning should treat `## First-Feature Bootstrap Decision` in the design artifact as the source of truth for bootstrap status, rather than re-checking repo emptiness or re-deciding bootstrap need independently.

Rationale: the user's requirement is not just to mention blueprints in design; the scaffold decision must affect the actual implementation plan.

## Risks / Trade-offs

- **Risk:** `ai/project_overmind.yaml` may be absent or may not yet carry class metadata in some runs.
  - **Mitigation:** treat missing class metadata as unresolved bootstrap input; if blueprint lookup is needed, stop and ask the user rather than guessing.
- **Risk:** "near-empty repo" can be interpreted loosely by the model.
  - **Mitigation:** require explicit yes/no bootstrap classification in the design artifact and add tests that verify the prompt contract and readiness behavior, not just prose suggestions.
- **Risk:** A generic blueprint may exist but still be a poor fit for the current feature.
  - **Mitigation:** design must record why the selected blueprint is relevant for the current class and current scaffold need; otherwise it is treated as unresolved and sent back to the user.
- **Risk:** Planning could mention scaffolding but bury it after feature tasks.
  - **Mitigation:** planning readiness should fail when first-feature bootstrap does not place scaffold creation into mandatory ordered work.

## Implementation Outline

1. Extend `ai/scripts/ai_design.sh` prompt contract to require bootstrap classification, blueprint lookup, and canonical scaffold handoff sections.
2. Add `ai/scripts/helpers/helper_find_blueprints.sh` to run from the current feature artifact context and search the parent project-level directory for class-scoped `project_stack_blueprint_*.md` candidates.
3. Update `ai/templates/feature_design_TEMPLATE.md` and its golden example to include the new sections.
4. Extend `ai/scripts/helpers/check_design_readiness.sh` and its spec contract so first-feature bootstrap cannot pass readiness without resolved scaffold handoff or explicit user decision.
5. Extend `ai/scripts/ai_plan.sh` prompt contract and `ai/templates/step_plan_TEMPLATE.md` so planning consumes `## Scaffold Creation Handoff` and emits `## Scaffold Bootstrap Plan`.
6. Extend `ai/scripts/helpers/check_planning_readiness.sh` and its spec contract so first-feature bootstrap cannot pass readiness unless scaffold creation is present in the plan as mandatory work.
7. Add targeted tests for blueprint-found, blueprint-missing, irrelevant-blueprint, and non-bootstrap cases.

## Open Questions

- What exact key in `ai/project_overmind.yaml` carries the project class today? The change assumes a stable class field exists or will be added as part of implementation.
- Whether the helper should return only matching files or also annotate why a candidate appears valid/invalid for scaffold use.
