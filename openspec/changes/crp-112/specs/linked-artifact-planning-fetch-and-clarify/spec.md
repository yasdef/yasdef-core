## ADDED Requirements

### Requirement: A dedicated helper MUST sync the in-scope LAR shortlist into the step plan
The planning prompt SHALL instruct the model to invoke `ai/scripts/helpers/sync_step_lars.sh <step> ai/step_plans/step-<N>.md` so the `## Linked Artifacts (in scope)` section lands deterministically in the step plan rather than being echoed by the model. `ai/scripts/ai_plan.sh` SHALL read `## Linked Artifacts (in scope)` from `ai/step_designs/step-<N>-design.md` for prompt context only; the artifact-side write to the step plan is delegated to the helper.

#### Scenario: Planning prompt instructs the model to invoke the sync helper
- **WHEN** `ai/scripts/ai_plan.sh` emits the planning prompt contract
- **THEN** the prompt instructs the model to invoke `ai/scripts/helpers/sync_step_lars.sh <step> ai/step_plans/step-<N>.md` for artifact-side syncing of the section
- **THEN** the prompt does not require the model to echo the `## Linked Artifacts (in scope)` block textually into the step plan

#### Scenario: Helper produces an idempotent step plan section
- **WHEN** the helper runs against an existing step plan that already contains a `## Linked Artifacts (in scope)` section
- **THEN** the section is replaced with the freshly recomputed section
- **THEN** running the helper again produces a byte-equivalent step plan

#### Scenario: Design artifact carries a non-empty shortlist
- **WHEN** the planning phase runs for a step whose design artifact contains a non-empty `## Linked Artifacts (in scope)` block
- **THEN** the planning prompt context contains the same `## Linked Artifacts (in scope)` block with identical entries in identical order
- **THEN** the step plan ends up with the same block via the sync helper

#### Scenario: Design artifact carries an empty or absent shortlist
- **WHEN** the planning phase runs for a step whose design artifact omits `## Linked Artifacts (in scope)` or emits it empty
- **THEN** the planning prompt context may omit the block entirely or emit it empty
- **THEN** the helper leaves the step plan with no `## Linked Artifacts (in scope)` section or an empty one

### Requirement: Planning prompt MUST instruct the model to fetch in-scope LAR locators as one more context input for the existing clarification loop
`ai/scripts/ai_plan.sh` SHALL include a single explicit rule line in the planning prompt directing the model to fetch each in-scope LAR locator using its available web/MCP tooling at the start of context-gathering, treat the fetched content as one more context input alongside `overmind/implementation_plan.md`, `overmind/reqirements_ears.md`, the design artifact, and ADRs, and route any fetch failure through the existing ask-user mechanisms (`ai/open_questions.md`, `ai/blocker_log.md`, two-option prompts) using the standard "cannot resolve LAR-NNN (locator: ...). How should I proceed?" question pattern.

#### Scenario: Fetch rule line is present when at least one LAR is in scope
- **WHEN** `ai/scripts/ai_plan.sh` emits the planning prompt contract for a step whose step plan will contain at least one `- LAR-NNN | <type> | <title> | <locator>` entry
- **THEN** the planning prompt contains the fetch-as-clarification-input rule line

#### Scenario: Fetch rule line is omitted when no LARs are in scope
- **WHEN** `ai/scripts/ai_plan.sh` emits the planning prompt contract for a step with no in-scope LAR entries
- **THEN** the fetch rule line may be omitted or rendered as a no-op statement

### Requirement: Planning clarification loop MUST consume fetched LAR content like any other input source without new ceremony
`ai/AI_DEVELOPMENT_PROCESS.md` Section 2.1 SHALL state that fetched LAR content participates in the existing planning clarification loop on equal footing with every other input source. There SHALL be no new "summarize fetched content and confirm with user" subroutine, no new artifact section for LAR summaries, and no new prompt subroutine. The existing mechanisms for `## Things to Decide`, `## Decisions Needed`, `ai/open_questions.md`, `ai/blocker_log.md`, two-option prompts, and FR translation absorb fetched LAR content the same way they absorb any other context.

#### Scenario: Fetched LAR content informs FR translation
- **WHEN** the planning model fetches an in-scope LAR and uses its content to write FRs
- **THEN** affected FRs may reference the LAR explicitly (e.g., "...— see LAR-002")
- **THEN** the FR text remains self-contained per the existing canonical FR template

#### Scenario: Fetched LAR content surfaces new clarification questions
- **WHEN** the planning model fetches an in-scope LAR and finds gaps the EARS missed (states, breakpoints, error cases, etc.)
- **THEN** the model surfaces those gaps through existing mechanisms (`## Things to Decide`, two-option prompts, `ai/open_questions.md`)
- **THEN** no new artifact section is created for LAR-derived gaps

#### Scenario: Fetch failure raises a standard clarification question
- **WHEN** the planning model attempts to fetch an in-scope LAR locator and the fetch fails (network error, timeout, 4xx/5xx, auth wall, ambiguous content)
- **THEN** the model raises the standard "cannot resolve LAR-NNN (locator: ...). How should I proceed?" question through existing ask-user mechanisms
- **THEN** the user's resolution (paste content directly, supply alternate URL, or remove the upstream reference) feeds back into the loop the same way any other user answer does

### Requirement: Planning closure MUST block on unresolved in-scope LAR fetch failures
The planning phase SHALL NOT close while any in-scope LAR locator is unreachable and the user has not explicitly resolved the failure through the clarification loop.

#### Scenario: Unresolved LAR fetch failure blocks planning closure
- **WHEN** an in-scope LAR locator is unreachable and the user has not provided alternate content or removed the upstream reference
- **THEN** the planning phase does not emit the standard planning completion line
- **THEN** the planning readiness helper exits non-zero

#### Scenario: User-resolved LAR fetch failure does not block planning closure
- **WHEN** an in-scope LAR locator is unreachable but the user has provided alternate content (or otherwise resolved the failure through the clarification loop) and the affected FRs no longer depend on a live fetch
- **THEN** the planning phase may emit the standard planning completion line
- **THEN** the planning readiness helper exits `0` for the LAR-related condition
