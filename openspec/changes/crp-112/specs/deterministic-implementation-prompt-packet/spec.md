## ADDED Requirements

### Requirement: Implementation prompt packet SHALL include the in-scope LAR shortlist sourced from the step plan
The implementation prompt packet generator SHALL include a `## Linked Artifacts (in scope)` section whose content is sourced byte-equivalently from `ai/step_plans/step-<N>.md`. The section SHALL appear in a fixed position in the deterministic ordering.

#### Scenario: Step plan carries a non-empty LAR shortlist
- **WHEN** implementation prompt content is generated for a step whose step plan contains a non-empty `## Linked Artifacts (in scope)` block
- **THEN** the prompt packet contains a `## Linked Artifacts (in scope)` section with identical entries in identical order

#### Scenario: Step plan carries an empty or absent LAR shortlist
- **WHEN** implementation prompt content is generated for a step whose step plan omits `## Linked Artifacts (in scope)` or emits it empty
- **THEN** the prompt packet may omit the section entirely or emit it empty
- **THEN** the rest of the prompt packet ordering is unchanged

#### Scenario: LAR section position is deterministic
- **WHEN** implementation prompt content is generated multiple times for unchanged inputs
- **THEN** the `## Linked Artifacts (in scope)` section appears at the same position in the prompt packet across runs

### Requirement: Implementation prompt packet SHALL include the fetch-and-don't-invent rule line when LARs are in scope
The implementation prompt packet generator SHALL include a single explicit fetch-and-don't-invent rule line that directs the model to fetch each in-scope LAR locator using its available web/MCP tooling before implementing FRs that reference it, and to stop and ask the user when fetch fails or content is ambiguous.

#### Scenario: Rule line is present when at least one LAR is in scope
- **WHEN** implementation prompt content is generated for a step whose step plan contains at least one `- LAR-NNN | <type> | <title> | <locator>` entry
- **THEN** the prompt packet contains the fetch-and-don't-invent rule line

#### Scenario: Rule line is omitted when no LARs are in scope
- **WHEN** implementation prompt content is generated for a step whose step plan has no in-scope LAR entries
- **THEN** the prompt packet may omit the fetch-and-don't-invent rule line or render it as a no-op

### Requirement: Implementation prompt packet generation SHALL remain byte-deterministic when LARs are in scope
For unchanged source artifacts and environment-independent generation inputs, emitted prompt bytes SHALL remain identical across repeated runs even when `## Linked Artifacts (in scope)` is non-empty.

#### Scenario: Same artifacts with LARs produce identical prompt bytes
- **WHEN** prompt generation runs multiple times with unchanged step plan, design, requirements sources, and an unchanged in-scope LAR shortlist
- **THEN** output byte content is identical across runs

#### Scenario: LAR ordering changes are test-detectable
- **WHEN** prompt-focused tests run
- **THEN** tests fail if the LAR shortlist position, ordering, or formatting regresses
