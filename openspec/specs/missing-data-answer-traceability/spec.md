## Purpose
Define deterministic traceability for missing-data answer entries so each recorded answer points to its exact destination in the BR summary.
## Requirements
### Requirement: Missing-data latest answers SHALL include deterministic BR destination pointers
Each populated entry under `## 6. Latest User Answers -> answers` in `overmind/product/missing_br_data.md` SHALL include only an explicit pointer to where the answer was written in `overmind/product/feature_br_summary.md`, without answer narrative text.

#### Scenario: Answer entry with destination pointer is accepted
- **WHEN** an `answers` entry includes a destination pointer to BR location
- **THEN** the entry SHALL satisfy traceability expectations for the missing-data loop

#### Scenario: Answer entry without destination pointer is rejected
- **WHEN** an `answers` entry omits the BR destination pointer
- **THEN** quality checks SHALL fail the artifact as non-traceable

### Requirement: Destination pointer format SHALL include section marker and field/item identifier
Destination pointers in `answers` entries SHALL include both the target section marker and specific field/item identifier (for example, `## 7. Business Rules and Decision Logic - BR-6`).

#### Scenario: Section marker without item identifier fails validation
- **WHEN** an `answers` entry references only a section and omits the target item id
- **THEN** quality checks SHALL fail because the mapping is not deterministic

#### Scenario: Section marker plus item identifier passes validation
- **WHEN** an `answers` entry references both section marker and field/item id
- **THEN** quality checks SHALL accept the pointer format

### Requirement: Missing-data guidance artifacts SHALL encode the same pointer contract
`overmind/rules/user_br_clarification_rule.md`, `overmind/rules/task_to_br_rule.md`, `overmind/templates/missing_br_data_TEMPLATE.md`, and `overmind/golden_examples/missing_br_data_GOLDEN_EXAMPLE.md` SHALL consistently require and demonstrate the same answer-to-destination pointer format.

#### Scenario: Contributor follows template and rule guidance
- **WHEN** contributors use the template and rules to populate latest answers
- **THEN** authored entries SHALL include explicit destination pointer fields in the documented canonical style and omit answer narrative text

### Requirement: Script tests SHALL enforce pointer presence and minimal format
Tests under `tests/ai_scripts/` SHALL include deterministic checks that fail when destination pointers are missing or incomplete and pass when both section marker and field/item id are present.

#### Scenario: Missing pointer test case fails
- **WHEN** tests evaluate an `answers` entry without a destination pointer
- **THEN** the test suite SHALL report a failure for traceability requirements

#### Scenario: Complete pointer test case passes
- **WHEN** tests evaluate an `answers` entry containing section marker and field/item id
- **THEN** the test suite SHALL report the entry as compliant

