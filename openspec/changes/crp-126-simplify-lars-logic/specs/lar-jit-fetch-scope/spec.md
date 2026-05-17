## ADDED Requirements

### Requirement: LAR content SHALL be fetched only at implementation phase
The system SHALL restrict LAR locator fetching via web/MCP tooling to the implementation phase. The planning phase SHALL NOT fetch LAR content; it SHALL only propagate the LAR shortlist mechanically via `sync_step_lars.sh`.

#### Scenario: Planning phase with in-scope LARs
- **WHEN** the planning phase runs and the design artifact contains a non-empty `## Linked Artifacts (in scope)` section
- **THEN** the planning prompt SHALL invoke `sync_step_lars.sh` to mirror the LAR shortlist into the step plan and SHALL NOT include a fetch rule or any instruction to fetch LAR locators via MCP

#### Scenario: Implementation phase with in-scope LARs
- **WHEN** the implementation phase runs and the step plan contains a non-empty `## Linked Artifacts (in scope)` section
- **THEN** the implementation prompt SHALL include a fetch rule instructing the AI to fetch each in-scope LAR locator via available web/MCP tooling before implementing any FR that references it

#### Scenario: Planning phase LAR context pack
- **WHEN** the planning prompt context pack is assembled
- **THEN** the design-extracted LAR shortlist SHALL be included as an informational section without any fetch instruction attached to it

#### Scenario: Design phase with in-scope LARs
- **WHEN** the design phase runs
- **THEN** LAR content SHALL NOT be fetched; the design phase is limited to running the LAR funnel via `sync_step_lars.sh` to populate the shortlist
