## ADDED Requirements

### Requirement: Implementation prompt MUST use deterministic two-source precedence
The implementation prompt generator MUST build its execution packet from `ai/step_plans/step-<N>.md` as primary execution source and `ai/step_designs/step-<N>-design.md` as scope/design source.

#### Scenario: Step-plan execution precedence is enforced
- **WHEN** implementation prompt content is generated
- **THEN** `## Plan (ordered)` and `## Applicable UR Shortlist` are extracted from the step plan and not replaced by design equivalents

#### Scenario: Design scope supplement is enforced
- **WHEN** implementation prompt content is generated
- **THEN** scope and design context is sourced from the design artifact after step-plan execution sections

### Requirement: Implementation prompt MUST include mandatory extracted fields with caps
The generator MUST include all mandatory extraction fields defined by this change, with deterministic caps/truncation policy per section.

#### Scenario: Required step-plan fields are present
- **WHEN** implementation prompt content is generated
- **THEN** it contains `## Plan (ordered)`, `## Applicable UR Shortlist`, anti-regression checklist, implementation constraints, tests, risks, decisions-needed content, and collected REQ/NFR tags

#### Scenario: Required design fields are present
- **WHEN** implementation prompt content is generated
- **THEN** it contains goal/in-scope/out-of-scope/non-goals, proposal/design details excerpt, risks/mitigations, ADR shortlist, AGENTS constraints, and codebase references excerpt

#### Scenario: Requirements inlining is tag-filtered
- **WHEN** REQ/NFR tags are collected from the step plan
- **THEN** only matching sections from `reqirements_ears.md` are included and full-file dump is not used unless all sections are explicitly tagged

### Requirement: Prompt structure MUST follow strict deterministic ordering
The implementation prompt output MUST follow a fixed ordering with no reordering based on optional section availability.

#### Scenario: Top-of-prompt ordering is stable
- **WHEN** implementation prompt content is generated
- **THEN** the first sections are: short phase contract, anti-regression checklist, and verbatim `## Plan (ordered)` execution list

#### Scenario: Downstream ordering is stable
- **WHEN** implementation prompt content is generated
- **THEN** constraints/tests/risks/accepted decisions appear before scope/design excerpts, which appear before linked requirements excerpts

### Requirement: Anti-regression checklist MUST be derived and bounded
The generator MUST produce an anti-regression checklist of at most 8 bullets derived from step-plan UR shortlist and applicable design user-review rules, de-duplicated by UR ID.

#### Scenario: Checklist uses UR-ID de-duplication
- **WHEN** overlapping UR IDs appear in step plan and design user-review rules
- **THEN** checklist output includes each UR ID once in first-appearance order

#### Scenario: Checklist appears near top
- **WHEN** implementation prompt content is generated
- **THEN** anti-regression checklist appears within the initial prompt block before deeper context sections

### Requirement: Prompt output MUST avoid duplicated long process prose
The prompt MUST reference `ai/AI_DEVELOPMENT_PROCESS.md` for detailed workflow rules and MUST NOT inline repeated long process paragraphs beyond the short phase contract.

#### Scenario: Process authority is referenced, not duplicated
- **WHEN** implementation prompt content is generated
- **THEN** it includes a short phase contract and references authoritative process sections without re-emitting long rule blocks

### Requirement: Prompt generation MUST be byte-deterministic for identical inputs
For unchanged source artifacts and environment-independent generation inputs, emitted prompt bytes MUST be identical across repeated runs.

#### Scenario: Same artifacts produce identical prompt bytes
- **WHEN** prompt generation is executed multiple times with unchanged step plan, design, and requirements sources
- **THEN** output byte content is identical

#### Scenario: Order/size regressions are test-detectable
- **WHEN** prompt-focused tests run
- **THEN** tests fail if required ordering, required top sections, or compactness bounds regress
