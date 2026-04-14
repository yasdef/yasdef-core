## Purpose
Define optional invocation-scoped `--feature_path` behavior for overmind product-artifact scripts and associated scanner/rule/test contracts.
## Requirements
### Requirement: Product-artifact and scanner scripts SHALL support an optional `--feature_path` override
The scripts `overmind/scripts/init_br_scaffold.sh`, `overmind/scripts/init_scan_repo_for_br.sh`, `overmind/scripts/init_task_to_br.sh`, `overmind/scripts/init_user_br_clarification.sh`, `overmind/scripts/init_br_check_ears_readiness.sh`, and `overmind/scripts/init_progress_scanner.sh` SHALL accept an optional `--feature_path <path>` argument for selecting the artifact root used in that invocation.

#### Scenario: Script runs without explicit feature path override
- **WHEN** any covered script is invoked without `--feature_path`
- **THEN** it SHALL use `overmind/product` as the artifact root

#### Scenario: Script runs with explicit feature path override
- **WHEN** any covered script is invoked with `--feature_path overmind/product/custom-folder`
- **THEN** it SHALL use `overmind/product/custom-folder` as the artifact root for that invocation

### Requirement: Product artifact paths SHALL be derived from selected feature root per script run
For each covered script invocation, all product-artifact file paths it reads, writes, validates, or reports SHALL be computed from the selected feature root rather than hardcoded `overmind/product` literals.

#### Scenario: Feature BR summary initializer writes selected root output
- **WHEN** `init_br_scaffold.sh` runs with or without `--feature_path`
- **THEN** it SHALL write `feature_br_summary.md` under the selected root and report that selected path in output

#### Scenario: Repo scan and user-input flows target selected root artifacts
- **WHEN** `init_scan_repo_for_br.sh` or `init_task_to_br.sh` builds model prompt context
- **THEN** target artifact paths in prompts SHALL reference the selected root for `feature_br_summary.md` and related product artifacts

#### Scenario: Missing-data loop and readiness gate resolve selected root artifacts
- **WHEN** `init_user_br_clarification.sh` or `init_br_check_ears_readiness.sh` reads or writes product artifacts
- **THEN** they SHALL use `missing_br_data.md`, `feature_br_summary.md`, and related product directory paths under the selected root

### Requirement: Progress scanner SHALL resolve product checklist paths from invocation-selected feature root
`init_progress_scanner.sh` SHALL keep existing YAML-driven checklist behavior and SHALL apply invocation-selected `--feature_path` when resolving product-root checklist targets, including Step 3 EARS conversion artifacts.

#### Scenario: Scanner default run preserves existing product-root checklist resolution
- **WHEN** `init_progress_scanner.sh` runs without `--feature_path` and checklist artifact entries target product root
- **THEN** scanner resolution SHALL continue using `overmind/product` semantics

#### Scenario: Scanner override run resolves product-root checklist targets to selected root
- **WHEN** `init_progress_scanner.sh` runs with `--feature_path overmind/product/custom-folder` and checklist artifact entries target product root
- **THEN** scanner SHALL resolve those product-root checklist targets under `overmind/product/custom-folder` for that invocation

#### Scenario: Scanner resolves Step 3 EARS artifact from selected feature root
- **WHEN** Step 3 requires `requirements_ears_feature.md`, scanner runs with `--feature_path overmind/product/custom-folder`, and the artifact exists at `overmind/product/custom-folder/requirements_ears_feature.md`
- **THEN** scanner SHALL evaluate Step 3 completion using that selected feature-root path

#### Scenario: Scanner override does not alter non-product checklist path resolution
- **WHEN** `init_progress_scanner.sh` runs with `--feature_path <path>` and checklist artifact entries target non-product folders
- **THEN** scanner SHALL preserve existing default and `special_folder` resolution behavior for those non-product entries

### Requirement: Model rule artifacts SHALL remain path-agnostic
Rule artifacts consumed by model-driven BR phases SHALL not hardcode `overmind/product/...` paths as fixed target locations.

#### Scenario: Repo scan rule avoids fixed product-root artifact target
- **WHEN** `overmind/rules/repo_br_scan_rule.md` is used during a run with `--feature_path <path>`
- **THEN** it SHALL not require a fixed `overmind/product/feature_br_summary.md` target that conflicts with the selected root

#### Scenario: User-input and missing-data loop rules avoid fixed product-root artifact targets
- **WHEN** `overmind/rules/task_to_br_rule.md` or `overmind/rules/user_br_clarification_rule.md` is used during a run with `--feature_path <path>`
- **THEN** they SHALL not require fixed `overmind/product/...` artifact paths that conflict with the selected root

### Requirement: Model-driven script prompts SHALL inject runtime-resolved artifact paths
For model-driven scripts, prompt context SHALL include runtime-resolved artifact paths derived from the invocation's selected feature root, and those runtime bindings SHALL be treated as authoritative for file targeting in that run.

#### Scenario: Repo scan prompt binds selected target artifact path
- **WHEN** `init_scan_repo_for_br.sh` runs with `--feature_path <path>`
- **THEN** its prompt context SHALL provide the resolved target BR artifact under `<path>` and SHALL direct model updates to that resolved target

#### Scenario: User-input prompt binds selected BR and missing-data artifact paths
- **WHEN** `init_task_to_br.sh` runs with `--feature_path <path>`
- **THEN** its prompt context SHALL provide resolved BR and missing-data artifact paths under `<path>` and SHALL direct model updates to those resolved targets

#### Scenario: Missing-data loop prompt binds selected artifacts and helper gate target
- **WHEN** `init_user_br_clarification.sh` runs with `--feature_path <path>`
- **THEN** its prompt context SHALL provide resolved BR and missing-data artifact paths under `<path>` and a helper gate command targeting the resolved BR path

### Requirement: Feature path override behavior SHALL remain stateless per invocation
The selected `--feature_path` value SHALL apply only to the invocation where it is passed and SHALL not persist to subsequent runs when omitted.

#### Scenario: Repeated invocation falls back to default after override run
- **WHEN** a covered script is run once with `--feature_path <path>` and later run without `--feature_path`
- **THEN** the later run SHALL use `overmind/product`

### Requirement: Feature path selection SHALL not be implicitly shared across scripts
Providing `--feature_path` to one covered script SHALL not affect artifact-root selection in later invocations of other covered scripts unless those invocations also pass the flag.

#### Scenario: One script override does not leak into another script run
- **WHEN** script A runs with `--feature_path <path>` and script B runs later without `--feature_path`
- **THEN** script B SHALL use `overmind/product`

### Requirement: Regression coverage SHALL enforce default, override, and isolation contracts
Shell tests under `tests/ai_scripts/` SHALL validate default-path behavior, override-path behavior, repeated-run statelessness, and cross-script isolation for the covered scripts. CRP-scoped contract tests under `tests/ai_scripts/crp-068/` SHALL pass for product-artifact scripts, and scanner behavior SHALL be validated in the scanner suite.

#### Scenario: Contract test suite validates feature path behavior
- **WHEN** `bash tests/ai_scripts/crp-068/feature_path_override_contract_tests.sh` is run from repository root
- **THEN** it SHALL pass and confirm default, override, stateless repeated-run, and cross-script isolation behavior for product-artifact scripts

#### Scenario: Progress scanner suite validates feature path behavior
- **WHEN** `bash tests/ai_scripts/init_progress_scanner_tests.sh` is run from repository root
- **THEN** it SHALL include coverage confirming scanner default and override resolution for product-root checklist targets

