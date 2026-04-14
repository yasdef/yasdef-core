## ADDED Requirements

### Requirement: Coordinator planning artifacts are owned under overmind
The project SHALL treat `overmind/implementation_plan.md` and `overmind/reqirements_ears.md` as canonical coordinator artifacts, and coordinator workflows MUST resolve these files from `/overmind` paths first.

#### Scenario: Coordinator flow resolves planning artifacts
- **WHEN** a coordinator-phase script prepares prompts or validates required planning inputs
- **THEN** it reads `implementation_plan.md` and `reqirements_ears.md` from `/overmind` canonical paths

#### Scenario: Legacy ai path is still present during migration
- **WHEN** legacy copies exist under `/ai`
- **THEN** `/overmind` paths remain the source of truth for coordinator behavior

### Requirement: Coordinator templates and golden examples are hosted under overmind
The project SHALL host templates and golden examples for coordinator-owned planning artifacts under `overmind/templates` and `overmind/golden_examples`.

#### Scenario: Template lookup for implementation plan
- **WHEN** a script or contributor needs the implementation plan template or example
- **THEN** the resolved path is under `/overmind/templates` or `/overmind/golden_examples`

#### Scenario: Template lookup for requirements EARS
- **WHEN** a script or contributor needs the requirements EARS template or example
- **THEN** the resolved path is under `/overmind/templates` or `/overmind/golden_examples`

### Requirement: Documentation reflects coordinator-worker artifact boundary
Project documentation SHALL describe `/overmind` as coordinator-owned artifact space and `/ai` as worker execution space.

#### Scenario: Worker quick-start references planning artifacts
- **WHEN** README or setup docs describe required planning artifacts
- **THEN** they reference `/overmind` for coordinator-owned files and avoid implying `/ai` ownership
