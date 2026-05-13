## ADDED Requirements

### Requirement: Implementation prompt MUST inject the in-scope LAR shortlist verbatim from the step plan
`ai/scripts/ai_implementation.sh` SHALL include the `## Linked Artifacts (in scope)` block from `ai/step_plans/step-<N>.md` in the implementation prompt context byte-equivalently to its source.

#### Scenario: Step plan carries a non-empty LAR shortlist
- **WHEN** `ai/scripts/ai_implementation.sh` builds the implementation prompt for a step whose `ai/step_plans/step-<N>.md` contains `## Linked Artifacts (in scope)` with one or more `- LAR-NNN | <type> | <title> | <locator>` lines
- **THEN** the implementation prompt context contains a `## Linked Artifacts (in scope)` block with identical entries in identical order

#### Scenario: Step plan carries an empty or missing LAR shortlist
- **WHEN** `ai/scripts/ai_implementation.sh` builds the implementation prompt for a step whose `ai/step_plans/step-<N>.md` omits `## Linked Artifacts (in scope)` or emits it empty
- **THEN** the implementation prompt may omit the `## Linked Artifacts (in scope)` block entirely or emit it empty
- **THEN** the rest of the implementation prompt is unchanged

### Requirement: Implementation prompt MUST instruct the model to fetch in-scope LAR locators for visual/detail fidelity that FR text cannot fully encode
`ai/scripts/ai_implementation.sh` SHALL include a single explicit fetch-for-visual-fidelity rule line in the implementation prompt directing the model to fetch each in-scope LAR locator using its available web/MCP tooling before implementing any FR that references that LAR, use the fetched content as source of truth for visual fidelity, exact spacing, icons, hover states, micro-interactions, mobile breakpoints, illustration crops, and other pixel/asset details that the FR text cannot fully encode, and stop and ask the user when fetch fails or fetched content is ambiguous.

#### Scenario: Fetch rule line is present in the implementation prompt
- **WHEN** `ai/scripts/ai_implementation.sh` emits the implementation prompt contract for a step whose step plan contains at least one `- LAR-NNN | <type> | <title> | <locator>` entry
- **THEN** the prompt contains a single rule line stating that the model SHALL fetch each in-scope LAR locator via available web/MCP tooling before implementing FRs that reference it, use the fetched content as source of truth for visual/detail fidelity, and stop and ask the user instead of inventing visual/detail content when fetch fails or content is ambiguous

#### Scenario: Fetch rule line is omitted when no LARs are in scope
- **WHEN** `ai/scripts/ai_implementation.sh` emits the implementation prompt contract for a step with no in-scope LAR entries
- **THEN** the fetch rule line may be omitted or rendered as a no-op statement

### Requirement: The implementation fetch rule MUST be the only authority for handling unfetchable or ambiguous LAR content during implementation
`ai/AI_DEVELOPMENT_PROCESS.md` Section 3.1 SHALL state that when an in-scope LAR locator cannot be fetched during implementation, returns ambiguous or unreadable content, or requires authentication the model does not have, the implementation phase SHALL stop and ask the user. The model SHALL NOT invent menu entries, copy text, schema fields, layout, spacing, icons, or other content covered by the LAR.

#### Scenario: Fetch fails at implementation runtime
- **WHEN** the model attempts to fetch an in-scope LAR locator during implementation and the fetch fails (network error, timeout, 4xx/5xx)
- **THEN** the model stops and asks the user how to proceed
- **THEN** the model does not generate implementation code that depends on the unfetched content

#### Scenario: Fetched content is ambiguous or unreadable at implementation runtime
- **WHEN** the model fetches an in-scope LAR locator but the response is a login page, an empty shell, or otherwise does not contain the artifact content needed to implement the dependent FR
- **THEN** the model stops and asks the user how to proceed
- **THEN** the model does not infer or invent the missing content

#### Scenario: Step has no in-scope LARs
- **WHEN** the implementation phase runs for a step whose in-scope LAR shortlist is empty or absent
- **THEN** no fetches are required
- **THEN** the implementation phase proceeds as it would without LAR awareness
