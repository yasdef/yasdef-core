## Purpose
Define the CRP-068 contract-test capability for stateless `--feature_path` override behavior across affected product-artifact scripts.
## Requirements
### Requirement: CRP-068 future contract tests SHALL live in a dedicated test folder
Tests for the stateless `--feature_path` override contract SHALL be added under `tests/ai_scripts/crp-068/` and SHALL remain scoped to CRP-068 behavior only.

#### Scenario: Contributor adds CRP-068 test assets
- **WHEN** the repository adds future-facing tests for `--feature_path`
- **THEN** those tests SHALL be stored under `tests/ai_scripts/crp-068/`
- **AND** they SHALL not require moving or rewriting existing top-level shell test suites

### Requirement: Contract tests SHALL cover default artifact-root behavior for each affected script
The CRP-068 test suite SHALL include cases proving that, when `--feature_path` is omitted, each affected product-artifact script still targets `overmind/product` as its artifact root.

#### Scenario: Script runs without feature path override
- **WHEN** a covered script is invoked without `--feature_path`
- **THEN** the corresponding test SHALL expect reads and writes under `overmind/product`

### Requirement: Contract tests SHALL cover explicit feature path override behavior for each affected script
The CRP-068 test suite SHALL include cases proving that, when `--feature_path <path>` is provided, each affected product-artifact script targets that provided artifact root for that invocation.

#### Scenario: Script runs with explicit feature path override
- **WHEN** a covered script is invoked with `--feature_path overmind/product/custom-folder`
- **THEN** the corresponding test SHALL expect product-artifact reads and writes under `overmind/product/custom-folder`

### Requirement: Contract tests SHALL enforce stateless per-invocation behavior
The CRP-068 test suite SHALL include cases proving that a `--feature_path` override applies only to the invocation where it is passed and does not persist to later invocations of the same script.

#### Scenario: Repeated invocation does not reuse prior override
- **WHEN** a script is run once with `--feature_path <path>` and then run again without that flag
- **THEN** the second-run test SHALL expect the script to return to `overmind/product`

### Requirement: Contract tests SHALL enforce no implicit path sharing between scripts
The CRP-068 test suite SHALL include cases proving that one script invocation does not implicitly supply its selected feature path to a different script invocation.

#### Scenario: Separate scripts do not share feature path state
- **WHEN** one covered script is invoked with `--feature_path <path>` and another covered script is invoked later without that flag
- **THEN** the second script’s test SHALL expect it to use `overmind/product`

### Requirement: Contract tests SHALL cover only product-artifact scripts affected by CRP-068
The CRP-068 test suite SHALL target only the scripts that currently read or write product artifacts through hardcoded `overmind/product` paths: `init_br_scaffold.sh`, `init_scan_repo_for_br.sh`, `init_task_to_br.sh`, `init_user_br_clarification.sh`, and `init_br_check_ears_readiness.sh`.

#### Scenario: Unrelated script is excluded from CRP-068 coverage
- **WHEN** a script does not own product-artifact path selection for this change
- **THEN** the CRP-068 test suite SHALL exclude it to keep the scope limited to the override contract

