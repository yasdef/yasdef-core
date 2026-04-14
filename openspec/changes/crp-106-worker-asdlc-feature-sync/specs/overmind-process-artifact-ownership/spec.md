## MODIFIED Requirements

### Requirement: Coordinator planning artifacts are owned under overmind
The selected ASDLC feature folder SHALL be the source of truth for coordinator planning artifacts, while local `overmind/implementation_plan.md` and `overmind/reqirements_ears.md` on branch `overmind` SHALL be synchronized worker runtime copies derived from that selected feature.

#### Scenario: Worker runtime copies are refreshed from the selected feature
- **WHEN** orchestrator prepares a run for one selected feature
- **THEN** it reads `implementation_plan.md` and `requirements_ears.md` from that selected feature folder
- **AND** it mirrors them into local `overmind/implementation_plan.md` and `overmind/reqirements_ears.md` on branch `overmind`

#### Scenario: Local overmind copies are not the source of truth
- **WHEN** local mirrored planning artifacts exist under `/overmind`
- **THEN** the selected ASDLC feature folder remains the source of truth for coordinator-owned inputs
- **AND** local `/overmind` copies are treated as synchronized worker runtime artifacts

### Requirement: Documentation reflects coordinator-worker artifact boundary
Project documentation SHALL describe selected ASDLC feature folders as the source of truth for coordinator planning artifacts and SHALL describe local `/overmind` files as synchronized worker runtime copies.

#### Scenario: Worker quick-start references planning artifacts
- **WHEN** README or setup docs describe worker prerequisites and feature execution inputs
- **THEN** they reference the selected ASDLC feature folder as the authoritative source
- **AND** they explain that local `/overmind` planning files are mirrored runtime copies used by worker phases
