## ADDED Requirements

### Requirement: Design MUST emit an explicit first-feature bootstrap decision
For every step, design SHALL state whether the step is the first implementation step on an empty or near-empty repo and SHALL record that outcome in a canonical bootstrap decision section.

#### Scenario: Design marks bootstrap required
- **WHEN** the current step is the first implementation step for an empty or near-empty repo
- **THEN** the design artifact records `Bootstrap required: yes`
- **THEN** the design artifact explains why scaffold creation is required for the current step

#### Scenario: Design marks bootstrap not required
- **WHEN** the current step extends an already-shaped implementation repo
- **THEN** the design artifact records `Bootstrap required: no`
- **THEN** planning is not required to add bootstrap scaffold work

### Requirement: Blueprint lookup MUST use the ASDLC project level above the current feature artifact folder and bound project class
When design determines bootstrap is required and stack or architecture guidance is needed, it SHALL run `ai/scripts/helpers/helper_find_blueprints.sh` from the ASDLC feature folder context where `implementation_plan.md` and `requirements_ears.md` live, and the helper SHALL check the parent project-level directory for blueprints while scoping lookup using the project class from `ai/project_overmind.yaml`.

#### Scenario: Backend bootstrap lookup uses project-level helper target
- **WHEN** the current feature path is `<project-level>/<feature-id>/`, the bound class is `back`, and design needs stack guidance
- **THEN** design runs `ai/scripts/helpers/helper_find_blueprints.sh` from `<project-level>/<feature-id>/`
- **THEN** the helper checks `<project-level>/`
- **THEN** blueprint candidates are filtered to backend-relevant `project_stack_blueprint_*.md` files

#### Scenario: Missing class metadata blocks automatic blueprint choice
- **WHEN** bootstrap is required and `ai/project_overmind.yaml` does not provide usable class metadata
- **THEN** design does not invent a class or blueprint choice
- **THEN** design asks the user how to proceed with stack selection

### Requirement: Valid blueprint evidence MUST be carried into the design handoff
If blueprint lookup finds a relevant blueprint that is suitable for scaffold creation for the current class, the design artifact SHALL include blueprint-backed scaffold handoff data in canonical sections that planning can consume directly.

#### Scenario: Relevant blueprint is included in design output
- **WHEN** blueprint lookup finds a relevant `project_stack_blueprint_*.md` file suitable for scaffold creation
- **THEN** the design artifact includes the blueprint path or identifier under `## Blueprint Context`
- **THEN** the design artifact includes scaffold creation intent and constraints under `## Scaffold Creation Handoff`

#### Scenario: Design handoff records scaffold dependency on blueprint
- **WHEN** design includes scaffold creation handoff for a first-feature bootstrap step
- **THEN** the handoff states that planning must preserve scaffold creation as mandatory work before dependent implementation tasks

### Requirement: Missing or irrelevant blueprint evidence MUST stop for user direction
If design determines bootstrap is required and blueprint lookup finds no relevant blueprint, or only finds blueprints that are not suitable for scaffold creation for the current class, design SHALL stop and ask the user how to proceed with stack selection instead of finishing normally.

#### Scenario: No blueprint files found
- **WHEN** bootstrap is required and the helper returns no `project_stack_blueprint_*.md` candidates relevant to the current class
- **THEN** design asks the user to decide the tech stack or scaffold direction
- **THEN** design does not emit the normal design completion line yet

#### Scenario: Only irrelevant blueprints found
- **WHEN** bootstrap is required and the helper finds blueprint files that do not fit the current class or current scaffold need
- **THEN** design asks the user how to proceed
- **THEN** planning does not start until that decision is resolved

### Requirement: Planning MUST preserve scaffold creation as mandatory first-feature work
When design records `Bootstrap required: yes`, planning SHALL consume the scaffold handoff and SHALL include scaffold creation as mandatory work in the step plan.

#### Scenario: Step plan includes scaffold bootstrap plan
- **WHEN** planning consumes a design artifact whose bootstrap decision is `yes`
- **THEN** the step plan includes a `## Scaffold Bootstrap Plan` section
- **THEN** the ordered plan contains scaffold creation work before any dependent feature implementation work

#### Scenario: Planning uses explicit design decision as bootstrap source of truth
- **WHEN** planning starts for a step whose design artifact contains `## First-Feature Bootstrap Decision`
- **THEN** planning reads bootstrap status from that design section
- **THEN** planning does not re-investigate repo state or independently re-decide whether the step is first-feature bootstrap

#### Scenario: Non-bootstrap design does not force scaffold section
- **WHEN** planning consumes a design artifact whose bootstrap decision is `no`
- **THEN** planning may omit `## Scaffold Bootstrap Plan`
- **THEN** normal feature planning behavior remains unchanged
