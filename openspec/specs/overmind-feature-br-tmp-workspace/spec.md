## Purpose
Define deterministic tmp-workspace allocation and active BR summary path resolution for BR authoring flows.

## ADDED Requirements

### Requirement: Initializer SHALL allocate BR tmp workspace with deterministic collision suffixing
`overmind/scripts/init_br_scaffold.sh` SHALL create the BR summary in `overmind/product/<tmp-slot>/feature_br_summary.md`, where `<tmp-slot>` is selected as `tmp`, then `tmp1`, `tmp2`, and so on using the first non-existing directory name.

#### Scenario: Base tmp slot is available
- **WHEN** `overmind/product/tmp` does not exist and initializer runs successfully
- **THEN** the script SHALL create `overmind/product/tmp/feature_br_summary.md`

#### Scenario: Base tmp slot already exists
- **WHEN** `overmind/product/tmp` exists and one or more suffixed slots may also exist
- **THEN** the script SHALL select the first available suffixed slot (`tmp1`, `tmp2`, ...) and create `feature_br_summary.md` there

### Requirement: BR summary consumers SHALL resolve active BR summary path from tmp workspace first
Related BR scripts SHALL resolve the active BR summary file by preferring `overmind/product/tmp*/feature_br_summary.md` and SHALL use deterministic precedence, with fallback to legacy `overmind/product/feature_br_summary.md` when no tmp workspace summary exists.

#### Scenario: Multiple tmp workspaces exist
- **WHEN** `overmind/product/tmp`, `overmind/product/tmp1`, and `overmind/product/tmp2` each contain `feature_br_summary.md`
- **THEN** resolver logic SHALL select the highest numeric suffix workspace (`tmp2`) as the active path

#### Scenario: No tmp workspace summary exists
- **WHEN** no `overmind/product/tmp*/feature_br_summary.md` file exists and legacy `overmind/product/feature_br_summary.md` exists
- **THEN** resolver logic SHALL use the legacy file path as the active BR summary target

### Requirement: Tmp workspace handling SHALL be regression-tested in canonical script test suites
Script tests under `tests/ai_scripts/` SHALL verify tmp-slot collision behavior and downstream path-resolution compatibility.

#### Scenario: Tmp collision and downstream flow are validated
- **WHEN** BR summary related test suites run from repository root
- **THEN** they SHALL verify deterministic `tmp/tmpN` allocation and successful downstream read/write/validation operations against the resolved active BR summary path
