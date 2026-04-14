## ADDED Requirements

### Requirement: Step-3 BR-to-EARS initializer SHALL exist as a deterministic overmind script
The system SHALL provide `overmind/scripts/init_br_to_ears.sh` as the canonical Step 3 initializer for converting validated BR summaries into feature-scoped EARS requirements.

#### Scenario: Initializer script is available at canonical path
- **WHEN** repository scripts are listed for overmind init phases
- **THEN** `overmind/scripts/init_br_to_ears.sh` SHALL exist as the Step 3 entrypoint

### Requirement: Initializer SHALL enforce overmind branch and stateless `--feature_path` handling
`init_br_to_ears.sh` SHALL run only on branch `overmind` and SHALL accept optional `--feature_path <path>` as its only runtime override, defaulting to `overmind/product` when omitted.

#### Scenario: Script runs on non-overmind branch
- **WHEN** `init_br_to_ears.sh` is invoked from a branch other than `overmind`
- **THEN** it SHALL exit non-zero with a meaningful branch enforcement error

#### Scenario: Script runs with feature-path override
- **WHEN** `init_br_to_ears.sh` is invoked with `--feature_path overmind/product/custom-folder`
- **THEN** it SHALL read `feature_br_summary.md` and write `requirements_ears.md` under `overmind/product/custom-folder`

### Requirement: Initializer SHALL validate required Step-3 inputs before model execution
Before invoking a model, `init_br_to_ears.sh` SHALL require the selected feature BR summary, `overmind/setup/models.md`, `overmind/rules/br_to_ears.md`, and `overmind/scripts/helper/check_requirements_ears_quality.sh`.

#### Scenario: Required Step-3 dependency is missing
- **WHEN** any required file is absent at invocation time
- **THEN** the script SHALL fail fast with a deterministic non-zero error naming the missing dependency

### Requirement: Initializer SHALL treat EARS readiness result as a hard prerequisite using read-only BR input
`init_br_to_ears.sh` SHALL fail unless `<feature_path>/feature_br_summary.md` declares `ready_to_ears: true`, SHALL treat `<feature_path>/feature_br_summary.md` as read-only input in Step 3, and SHALL direct the operator to `overmind/scripts/init_br_check_ears_readiness.sh` as the canonical prerequisite gate when readiness is not satisfied.

#### Scenario: BR summary is not EARS-ready
- **WHEN** `ready_to_ears` is missing or not `true` in the selected BR summary
- **THEN** the script SHALL exit non-zero and instruct running `overmind/scripts/init_br_check_ears_readiness.sh` first

#### Scenario: BR summary is EARS-ready
- **WHEN** the selected BR summary includes `ready_to_ears: true`
- **THEN** the script SHALL continue to Step 3 model invocation flow

### Requirement: Initializer SHALL load and execute the dedicated `br_to_ears` model phase
`init_br_to_ears.sh` SHALL load command/model/extra args from `overmind/setup/models.md` using phase key `br_to_ears`, validate that the command is `codex`, and execute the model with prompt context bound to selected runtime paths.

#### Scenario: br_to_ears phase is configured
- **WHEN** `overmind/setup/models.md` contains a valid `br_to_ears | codex | <model> | ...` row
- **THEN** the script SHALL execute `codex` with that model and optional arguments

#### Scenario: br_to_ears phase is missing or invalid
- **WHEN** `br_to_ears` configuration is absent or malformed in `overmind/setup/models.md`
- **THEN** the script SHALL fail fast with a deterministic configuration error

### Requirement: Initializer SHALL generate feature-scoped EARS output and commit only the Step-3 output file
After successful model execution, `init_br_to_ears.sh` SHALL ensure `<feature_path>/requirements_ears.md` exists and SHALL stage/commit only `<feature_path>/requirements_ears.md`.

#### Scenario: Model run succeeds and updates Step-3 output
- **WHEN** the model finishes with valid BR-to-EARS output
- **THEN** `<feature_path>/requirements_ears.md` SHALL exist and be included in the Step 3 commit scope

#### Scenario: No Step-3 artifact changes are produced
- **WHEN** `<feature_path>/requirements_ears.md` is unchanged after invocation
- **THEN** the script SHALL not create an empty commit

#### Scenario: Step-3 does not mutate BR summary input
- **WHEN** `init_br_to_ears.sh` runs successfully
- **THEN** it SHALL NOT modify `<feature_path>/feature_br_summary.md`

### Requirement: Step-3 initializer behavior SHALL be covered by shell regression tests
Regression tests under `tests/ai_scripts/` SHALL validate branch enforcement, readiness prerequisite enforcement, model invocation from `br_to_ears` configuration, and feature-path override behavior.

#### Scenario: Step-3 test suite runs from repository root
- **WHEN** the BR-to-EARS initializer test suite is executed from the repository root
- **THEN** it SHALL verify all required branch, prerequisite, model, and override behaviors deterministically
