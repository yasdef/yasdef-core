## ADDED Requirements

### Requirement: Design SHALL be the single funnel point for step-scoped LAR shortlists
The design phase SHALL own LAR funneling from `overmind/reqirements_ears.md` and SHALL emit the in-scope LAR shortlist into the design artifact via `ai/scripts/helpers/sync_step_lars.sh`. Downstream phases SHALL consume the in-scope LAR shortlist from the upstream artifact: planning from the design artifact, implementation from the step plan.

#### Scenario: Design extracts and emits the in-scope LAR shortlist
- **WHEN** the design phase runs for a step whose extracted `### Requirement N` blocks contain `**Linked Artifacts:**` references
- **THEN** the design prompt context emits the `## Linked Artifacts (in scope)` block built from the bottom `## Linked Artifacts` registry of `overmind/reqirements_ears.md`
- **THEN** the design artifact contains the same block via the sync helper

#### Scenario: Planning consumes LAR data from the design artifact
- **WHEN** the planning phase needs LAR data for a step
- **THEN** it reads `## Linked Artifacts (in scope)` from `ai/step_designs/step-<N>-design.md`

#### Scenario: Implementation consumes LAR data from the step plan
- **WHEN** the implementation phase needs LAR data for a step
- **THEN** it reads `## Linked Artifacts (in scope)` from `ai/step_plans/step-<N>.md`

### Requirement: Process documentation SHALL describe the LAR boundary model
`ai/AI_DEVELOPMENT_PROCESS.md` and `Readme.md` SHALL describe the LAR boundary model: design owns funneling and propagates the shortlist, planning mirrors via the sync helper and fetches in-scope locators as a clarification-loop input, and implementation fetches in-scope locators for visual/detail fidelity.

#### Scenario: Process doc states design ownership of LAR funneling
- **WHEN** operators read `ai/AI_DEVELOPMENT_PROCESS.md`
- **THEN** Section 1 (Design) explicitly states design extracts the in-scope LAR shortlist and propagates it without fetching
- **THEN** Section 2.1 (Planning) explicitly states planning mirrors the LAR shortlist verbatim into the step plan
- **THEN** Section 3.1 (Implementation) explicitly states implementation fetches in-scope locators and stops to ask the user instead of inventing content

#### Scenario: README repeats the LAR boundary model
- **WHEN** operators read `Readme.md`
- **THEN** the worker cycle description mentions LAR flow from design to plan to implementation
