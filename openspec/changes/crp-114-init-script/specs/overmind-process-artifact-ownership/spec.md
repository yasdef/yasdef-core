## MODIFIED Requirements

### Requirement: Coordinator planning artifacts are owned under overmind
The project SHALL treat ASDLC feature-folder `implementation_plan.md` and `requirements_ears.md` files as source-of-truth coordinator artifacts. Worker runtime copies SHALL be stored under `.asdlc_worker/overmind/implementation_plan.md` and `.asdlc_worker/overmind/reqirements_ears.md` for phase execution.

#### Scenario: Worker flow resolves runtime planning artifacts
- **WHEN** a worker phase script prepares prompts or validates required planning inputs
- **THEN** it reads `implementation_plan.md` and `reqirements_ears.md` from `.asdlc_worker/overmind` runtime paths

#### Scenario: Source-of-truth artifacts remain in ASDLC project feature folder
- **WHEN** orchestrator selects a feature from the bound ASDLC project repo
- **THEN** it treats that feature folder's `implementation_plan.md` and `requirements_ears.md` as source-of-truth inputs
- **AND** it mirrors them into `.asdlc_worker/overmind` before worker phase execution

### Requirement: Coordinator templates and golden examples are hosted under overmind
The worker runtime SHALL host worker-consumed templates and golden examples under `.asdlc_worker/templates` and `.asdlc_worker/golden_examples`.

#### Scenario: Template lookup for implementation plan
- **WHEN** a script or contributor needs a worker runtime template
- **THEN** the resolved path is under `.asdlc_worker/templates` or `.asdlc_worker/golden_examples`

#### Scenario: Template lookup for requirements EARS
- **WHEN** a script or contributor needs a worker runtime example
- **THEN** the resolved path is under `.asdlc_worker/templates` or `.asdlc_worker/golden_examples`
