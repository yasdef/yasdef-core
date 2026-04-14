## ADDED Requirements

### Requirement: Test layout rule is reflected in AGENTS guidance
The canonical external test-location rule MUST be documented in root `AGENTS.md` so execution guidance matches repository structure.

#### Scenario: AGENTS aligns with externalized test layout
- **WHEN** test layout guidance is read from `AGENTS.md`
- **THEN** it specifies `tests/ai_scripts/` as the canonical location and indicates that `ai/` is not the active test source path
