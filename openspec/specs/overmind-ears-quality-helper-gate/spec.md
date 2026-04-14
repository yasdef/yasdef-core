## ADDED Requirements

### Requirement: Post-conversion helper SHALL validate target artifact existence and non-empty content
The system SHALL require `overmind/scripts/helper/check_requirements_ears_quality.sh` to fail deterministically when the target EARS artifact is missing or empty.

#### Scenario: Target artifact missing
- **WHEN** the helper is invoked with a target path that does not exist
- **THEN** the helper SHALL exit with code `2` and SHALL emit a helper failure message naming the missing path

#### Scenario: Target artifact empty
- **WHEN** the helper is invoked with an existing target artifact that has no requirement content
- **THEN** the helper SHALL exit with code `1` and SHALL emit a content-quality failure message

### Requirement: Helper SHALL require at least one Requirement or NFR block
The helper SHALL require at least one `### Requirement <N>` or `### NFR <N>` block in the target artifact.

#### Scenario: No requirement blocks found
- **WHEN** the target artifact has no valid Requirement/NFR headings
- **THEN** the helper SHALL exit with code `1` and SHALL report that no Requirement/NFR blocks were found

### Requirement: Helper SHALL enforce required block fields
For every Requirement/NFR block, the helper SHALL require `User Story`, `Acceptance Criteria (EARS)`, and `Verification` fields.

#### Scenario: Block missing required field
- **WHEN** any Requirement/NFR block omits one required field
- **THEN** the helper SHALL exit with code `1` and SHALL identify the block and missing field

### Requirement: Helper SHALL enforce EARS criteria bullets
The helper SHALL require each acceptance-criteria section to contain at least one EARS-style bullet using allowed patterns and SHALL reject mixed-obligation bullets.

#### Scenario: Acceptance section has no EARS-style bullet
- **WHEN** a block has `Acceptance Criteria (EARS)` but no valid EARS-pattern bullet
- **THEN** the helper SHALL exit with code `1` and SHALL report an acceptance-criteria quality failure

#### Scenario: Acceptance bullet mixes independent obligations
- **WHEN** an acceptance bullet combines independent obligations that violate one-obligation-per-bullet guidance
- **THEN** the helper SHALL exit with code `1` and SHALL report the offending bullet

### Requirement: Helper SHALL enforce deterministic numbering without duplicates
The helper SHALL enforce deterministic, non-duplicated numbering for Requirement and NFR headings.

#### Scenario: Duplicate numbering detected
- **WHEN** two Requirement headings or two NFR headings reuse the same numeric identifier
- **THEN** the helper SHALL exit with code `1` and SHALL report duplicate numbering

#### Scenario: Numbering sequence is malformed
- **WHEN** heading numbering is non-deterministic for Requirement/NFR blocks
- **THEN** the helper SHALL exit with code `1` and SHALL report numbering quality failure

### Requirement: Helper SHALL use deterministic exit semantics
The helper SHALL use exit code `0` for pass, `1` for content-quality failure, and `2` for helper/script failure.

#### Scenario: Artifact passes all quality checks
- **WHEN** all validation checks pass
- **THEN** the helper SHALL exit with code `0`

#### Scenario: Helper runtime failure occurs
- **WHEN** helper execution cannot complete due to script/runtime failure
- **THEN** the helper SHALL exit with code `2`

### Requirement: Caller integration SHALL honor invocation-selected feature path
`overmind/scripts/init_br_to_ears.sh` SHALL run the quality helper against the EARS artifact resolved from the current invocation's `--feature_path` (or default feature root when omitted).

#### Scenario: Caller runs with default feature root
- **WHEN** `init_br_to_ears.sh` runs without `--feature_path`
- **THEN** helper validation SHALL target `overmind/product/requirements_ears.md`

#### Scenario: Caller runs with feature-path override
- **WHEN** `init_br_to_ears.sh` runs with `--feature_path overmind/product/custom-folder`
- **THEN** helper validation SHALL target `overmind/product/custom-folder/requirements_ears.md` for that invocation

### Requirement: Script tests SHALL cover helper quality outcomes and feature-path invocation
The repository SHALL include script tests under `tests/ai_scripts/` for helper pass/fail cases, duplicate-id detection, missing-field failures, and `--feature_path` usage through caller invocation.

#### Scenario: Quality helper contract tests run from repository root
- **WHEN** the CRP-072 script test suite is executed from repository root
- **THEN** it SHALL validate pass, fail, duplicate-id, missing-field, and caller `--feature_path` contract behavior
