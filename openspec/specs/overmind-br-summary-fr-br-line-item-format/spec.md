## Purpose
Define the BR-summary FR/BR one-line item contract and corresponding task-to-BR guidance expectations.
## Requirements
### Requirement: BR summary FR and BR sections SHALL use one-line numbered line items
The BR summary contract SHALL represent each Functional Requirement and Business Rule as a single concise line item with explicit IDs in sections `## 6. Functional Requirements` and `## 7. Business Rules and Decision Logic`.

#### Scenario: Template encodes one-line FR and BR placeholders
- **WHEN** `overmind/templates/feature_br_summary_TEMPLATE.md` is used to initialize BR summary structure
- **THEN** `## 6` SHALL include line items in `FR-N` form and `## 7` SHALL include line items in `BR-N` form without nested per-item key blocks

#### Scenario: One-line entries remain concise and business-readable
- **WHEN** FR and BR lines are populated during enrichment
- **THEN** each item SHALL remain a single concise business statement on one line

### Requirement: FR and BR cardinality SHALL be open-ended
The BR summary contract SHALL allow as many FR and BR items as needed to reflect actual business scope and SHALL NOT imply a fixed maximum item count.

#### Scenario: Template guidance does not imply fixed item limit
- **WHEN** contributors read template instructions for sections `## 6` and `## 7`
- **THEN** guidance SHALL explicitly state `FR-N` and `BR-N` are open-ended and expanded as needed

#### Scenario: Golden example demonstrates non-two-item cardinality
- **WHEN** contributors use `overmind/golden_examples/feature_br_summary_GOLDEN_EXAMPLE.md` as reference
- **THEN** the example SHALL show more than two FR items and more than two BR items

### Requirement: User-input BR enrichment guidance SHALL align with one-line FR and BR contract
Rule and helper-facing guidance for task-to-BR SHALL reference one-line FR and BR items and SHALL NOT require nested FR `title` or `description` item structure.

#### Scenario: Rule guidance references line-item structure
- **WHEN** `overmind/rules/task_to_br_rule.md` defines quality expectations
- **THEN** it SHALL require meaningful one-line FR and BR items and SHALL not require paired nested keys such as `title` and `description`

#### Scenario: Missing-data and helper messaging reflects one-line contract
- **WHEN** missing business-context output references FR requirements
- **THEN** wording SHALL describe one-line FR item expectations instead of legacy nested field expectations

### Requirement: Script tests SHALL enforce one-line FR/BR contract semantics
Tests under `tests/ai_scripts/` SHALL validate one-line FR/BR structure expectations and SHALL reject regressions back to fixed two-item or nested-only assumptions.

#### Scenario: User-input gate tests validate one-line FR acceptance
- **WHEN** helper and user-input stage tests run
- **THEN** they SHALL pass when at least one meaningful one-line FR item is present in `## 6`

#### Scenario: Regression tests detect legacy-structure assumptions
- **WHEN** test assertions reference FR/BR quality messaging
- **THEN** they SHALL align with one-line line-item contract terminology

