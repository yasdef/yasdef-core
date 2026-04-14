## ADDED Requirements

### Requirement: Root AGENTS guidance file exists
The repository MUST provide a root-level `AGENTS.md` that defines baseline project-specific AI/developer operating rules.

#### Scenario: AGENTS file is available at repository root
- **WHEN** a contributor or AI workflow loads project guidance
- **THEN** `AGENTS.md` exists at repository root and is readable as the canonical project rule source

### Requirement: AGENTS includes required baseline sections
`AGENTS.md` MUST include concise baseline guidance covering project context, command/test execution expectations, safety constraints for changes, and maintenance expectations.

#### Scenario: Baseline sections are present
- **WHEN** `AGENTS.md` is reviewed
- **THEN** it contains actionable sections for project context, required commands/tests, change safety rules, and update expectations

### Requirement: AGENTS test-location rule is explicit
`AGENTS.md` MUST explicitly state the canonical script-test location and invocation path conventions.

#### Scenario: Test location rule is documented
- **WHEN** a contributor looks up test guidance in `AGENTS.md`
- **THEN** the file clearly states that script tests run from `tests/ai_scripts/` and not from paths under `ai/`
