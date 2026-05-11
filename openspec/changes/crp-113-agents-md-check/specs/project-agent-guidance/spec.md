## ADDED Requirements

### Requirement: Init worker guidance references class blueprint when available
When the worker repo root lacks `AGENTS.md`, worker initialization SHALL use the resolved worker class to check the bound ASDLC project repo root for `project_stack_blueprint_<project_class>.md` and include that blueprint path in the guidance warning when it exists.

#### Scenario: Missing AGENTS with matching blueprint
- **WHEN** the current worker repo root does not contain `AGENTS.md`
- **AND** the bound ASDLC project repo root contains `project_stack_blueprint_<project_class>.md` for the resolved worker class
- **THEN** the worker init script prints `⚠️  before start implementing things, ask model to create AGENTS.md, pass <path-to-blueprint> to your prompt so model can use best practices`

#### Scenario: Missing AGENTS without matching blueprint
- **WHEN** the current worker repo root does not contain `AGENTS.md`
- **AND** the bound ASDLC project repo root does not contain `project_stack_blueprint_<project_class>.md` for the resolved worker class
- **THEN** the worker init script prints `⚠️  before start implementing things, dont forget to create AGENTS.md`

#### Scenario: Blueprint lookup uses project root
- **WHEN** the worker init script checks for a class-specific blueprint
- **THEN** it resolves the blueprint path under the same bound ASDLC project repo root that contains `init_progress_definition.yaml`
