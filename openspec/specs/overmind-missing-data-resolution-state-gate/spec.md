## Purpose
Define the missing-data ledger state model so tracking state and resolution state are handled separately and deterministically.
## Requirements
### Requirement: Newly externalized missing-data items SHALL start with unresolved raised state
When unresolved business items are first written into `overmind/product/missing_br_data.md` by the task-to-BR flow, each created ledger item SHALL set `rised=false` and `resolved=false`.

#### Scenario: Rule-driven externalization creates initial unresolved state
- **WHEN** `overmind/rules/task_to_br_rule.md` externalizes a new unresolved item from BR sections into `missing_br_data.md`
- **THEN** the created ledger line SHALL include `rised=false` and `resolved=false`

### Requirement: Missing-data loop initializer SHALL gate on unresolved resolution state
`overmind/scripts/init_user_br_clarification.sh` SHALL treat items as unresolved unless they are explicitly marked `resolved=true`, and SHALL invoke the loop when unresolved items remain.

#### Scenario: Loop runs when unresolved items exist
- **WHEN** `overmind/product/missing_br_data.md` contains at least one tracked ledger item without `resolved=true`
- **THEN** `init_user_br_clarification.sh` SHALL run the clarification loop

#### Scenario: Loop skips when all tracked items are resolved
- **WHEN** every tracked ledger item in `overmind/product/missing_br_data.md` is marked `resolved=true`
- **THEN** `init_user_br_clarification.sh` SHALL skip loop execution with deterministic no-op messaging

### Requirement: Resolution transition SHALL occur only after BR answer write-back
A missing-data ledger item SHALL transition from unresolved to resolved only after corresponding answer content is written into `overmind/product/feature_br_summary.md`, while `missing_br_data.md` remains status/reference-only.

#### Scenario: Item is marked resolved after answer persistence
- **WHEN** the loop captures a usable business answer for an unresolved item
- **THEN** the implementation SHALL first apply answer content in `feature_br_summary.md` and then mark the ledger item `resolved=true` with answer reference metadata

#### Scenario: Ledger does not duplicate answer body text
- **WHEN** an item is marked `resolved=true`
- **THEN** `missing_br_data.md` SHALL store status and answer reference metadata only, and SHALL NOT duplicate full answer text stored in `feature_br_summary.md`

### Requirement: Missing-data format artifacts and tests SHALL enforce split state semantics
Template, golden example, and test suites SHALL represent and verify separate tracking vs resolution states.

#### Scenario: Canonical artifacts encode lifecycle flags
- **WHEN** contributors use `overmind/templates/missing_br_data_TEMPLATE.md` or `overmind/golden_examples/missing_br_data_GOLDEN_EXAMPLE.md`
- **THEN** unresolved examples SHALL include `resolved=false` and resolved examples SHALL include `resolved=true`

#### Scenario: Regression tests validate loop-entry and completion semantics
- **WHEN** `tests/ai_scripts/init_user_br_clarification_tests.sh` runs
- **THEN** it SHALL verify loop invocation for unresolved items and no-op behavior for all-resolved ledgers

