## ADDED Requirements

### Requirement: Repo scan initializer SHALL run a post-fill business-context quality gate
`overmind/scripts/init_scan_repo_for_br.sh` SHALL execute `overmind/scripts/helper/check_business_context_filled_from_repo.sh` after the model updates the resolved active BR summary file path and before declaring success.

#### Scenario: Model run produces target BR summary
- **WHEN** `init_scan_repo_for_br.sh` finishes a model invocation and the resolved active BR summary file exists
- **THEN** the script SHALL run `overmind/scripts/helper/check_business_context_filled_from_repo.sh` as a post-fill quality gate before any commit or success message

### Requirement: Quality gate SHALL validate required business-context completeness
`overmind/scripts/helper/check_business_context_filled_from_repo.sh` SHALL fail when required fields are unfilled and SHALL pass only when required fields are filled in the target BR summary.

#### Scenario: Required fields are complete
- **WHEN** `## 1. Document Meta` contains filled `last_updated` and `source_type` values and all required fields under `## 13. Existing-System Context` are filled
- **THEN** the helper script SHALL exit with code `0`

#### Scenario: Required fields are incomplete
- **WHEN** any required field in `## 1. Document Meta` (`last_updated`, `source_type`) or `## 13. Existing-System Context` remains `[UNFILLED]`, empty, or missing
- **THEN** the helper script SHALL exit non-zero and report that the business-context gate failed

### Requirement: Commit behavior SHALL be gated by quality-gate success
`init_scan_repo_for_br.sh` SHALL commit the resolved active BR summary file only after a successful quality gate.

#### Scenario: Gate passes
- **WHEN** the post-fill gate exits `0`
- **THEN** the script SHALL proceed with the existing commit path for the resolved active BR summary file and print the success output

#### Scenario: Gate fails
- **WHEN** the post-fill gate exits non-zero
- **THEN** the script SHALL NOT commit the resolved active BR summary file in that attempt

### Requirement: Gate failure handling SHALL require explicit user approval to retry
On gate failure, `init_scan_repo_for_br.sh` SHALL analyze/report failure and SHALL ask the user whether retry is allowed before running another model pass.

#### Scenario: User approves retry
- **WHEN** the gate fails and user explicitly allows retry
- **THEN** the script SHALL run another model invocation followed by the same post-fill quality gate

#### Scenario: User declines retry
- **WHEN** the gate fails and user does not approve retry
- **THEN** the script SHALL exit non-zero without committing and without entering further retry attempts

### Requirement: Repo-scan rule file SHALL include explicit gate section
`overmind/rules/repo_br_scan_rule.md` SHALL include an additional quality-gate instruction section with `Gate` postfix naming for post-fill validation behavior.

#### Scenario: Rule file is used by repo scan initializer
- **WHEN** `init_scan_repo_for_br.sh` builds the prompt using `overmind/rules/repo_br_scan_rule.md`
- **THEN** the rule content SHALL include a dedicated `... Gate` block instructing the model about post-fill gate expectations

### Requirement: Script tests SHALL cover pass, fail, and retry paths for the gate
`tests/ai_scripts/init_scan_repo_for_br_tests.sh` SHALL validate the quality-gate outcomes and retry interaction.

#### Scenario: Test suite validates gate behavior
- **WHEN** the repo-scan initializer tests run from repository root
- **THEN** they SHALL cover gate success, gate failure without retry approval, and gate failure with user-approved retry
