## ADDED Requirements

### Requirement: New UR entries MUST follow template-complete schema
When adding a new entry to `ai/user_review.md`, the entry MUST contain all required fields from `ai/templates/user_review_TEMPLATE.md`: `Trigger`, `Rule`, `How to verify`, `Example(s)`, and `References`.

#### Scenario: Template-complete entry passes validation
- **WHEN** a newly added UR entry includes all required fields
- **THEN** UR validation reports the entry as structurally valid

#### Scenario: Missing required field fails validation
- **WHEN** a newly added UR entry omits any required field
- **THEN** UR validation fails with the missing field name and entry identifier

### Requirement: Duplicate UR IDs MUST be rejected
UR additions MUST NOT introduce an ID that already exists in `ai/user_review.md`.

#### Scenario: Duplicate UR ID is added
- **WHEN** a new UR entry uses an existing `UR-xxxx` identifier
- **THEN** UR validation fails and identifies the conflicting ID

### Requirement: Exact overlap additions MUST be rejected
New UR entries MUST NOT duplicate an existing rule intent using the same normalized `Trigger` + `Rule` content.

#### Scenario: Overlapping trigger/rule is added under new ID
- **WHEN** a new UR entry has normalized `Trigger` and `Rule` matching an existing entry
- **THEN** UR validation fails and instructs updating the existing UR entry instead of adding a duplicate

### Requirement: Non-generalizable feedback uses step-specific fallback
If review feedback cannot be expressed with template-complete UR fields, it MUST be recorded as a step-specific note in the active step plan rather than added to `ai/user_review.md`.

#### Scenario: Feedback lacks enough detail for template fields
- **WHEN** feedback cannot provide actionable `How to verify` or references
- **THEN** process guidance records it in the step plan and does not create a new UR entry
