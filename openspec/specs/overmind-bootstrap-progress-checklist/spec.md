## Purpose
Define the overmind progress-checklist scanner contract, including artifact gating, output format, and feature-root-aware evaluation semantics.
## Requirements
### Requirement: Bootstrap checklist definition SHALL be data-driven in YAML
The system SHALL define ordered bootstrap steps in `overmind/init_progress_definition.yaml`. Each step SHALL continue to declare always-required evidence artifacts under `finished_only_if_artefacts_present` (strict AND semantics), and MAY additionally declare artifact groups under `finished_only_if_artefact_groups`. Artifact entries in both structures MAY include `check_key_value` with `key`, `equals`, and `section`.

#### Scenario: Scanner reads ordered step contract from YAML
- **WHEN** `overmind/scripts/init_progress_scanner.sh` runs
- **THEN** it SHALL evaluate steps in YAML order using `step_number` and `step_name`

#### Scenario: Step completion includes required artifact list and optional group constraints
- **WHEN** a step defines entries in `finished_only_if_artefacts_present` and one or more `finished_only_if_artefact_groups`
- **THEN** the scanner SHALL require all listed required artifacts
- **AND** SHALL require every declared group to satisfy its configured mode

#### Scenario: Group entries may reuse artifact fields
- **WHEN** a group entry defines `file` with optional `special_folder` and optional `check_key_value`
- **THEN** scanner artifact matching for that entry SHALL use the same path and key/value rules as base required artifacts

### Requirement: Scanner SHALL evaluate artifact presence using default and override folders
The scanner SHALL use `overmind/` as default search root, SHALL support per-artifact `special_folder` overrides, SHALL evaluate optional section-scoped `check_key_value`, and SHALL apply the same folder and content-check behavior for group entries.

#### Scenario: Default overmind folder is used when no override is defined
- **WHEN** a required artifact or group artifact entry contains only `file`
- **THEN** the scanner SHALL resolve presence against the `overmind/` directory

#### Scenario: Special folder override is used when declared
- **WHEN** a required artifact or group artifact entry includes `special_folder`
- **THEN** the scanner SHALL resolve that artifact in the specified folder instead of default `overmind/`

#### Scenario: Section-scoped key/value check passes
- **WHEN** a required artifact or group artifact entry includes `check_key_value` and the target file contains `<key>: <equals>` inside the configured section
- **THEN** that artifact entry SHALL be marked complete

#### Scenario: Section-scoped key/value check fails
- **WHEN** a required artifact or group artifact entry includes `check_key_value` and the target file is missing the key or has a non-matching value within the configured section
- **THEN** that artifact entry SHALL be marked incomplete

### Requirement: Scanner SHALL enforce overmind-branch context before scanning
Before evaluating artifacts, the scanner SHALL switch to branch `overmind` and SHALL stop with an explicit error when branch transition is not possible.

#### Scenario: Scanner starts from a non-overmind branch
- **WHEN** scanner execution begins on another branch
- **THEN** it SHALL switch to `overmind` before artifact evaluation continues

#### Scenario: Scanner cannot establish overmind branch context
- **WHEN** checkout to `overmind` fails
- **THEN** the scanner SHALL exit non-zero and SHALL NOT write a success-like checklist state

### Requirement: Scanner output SHALL be deterministic and model-friendly
The scanner SHALL generate `overmind/step_state.md` with one checklist line per step in declared order using `[x]` for complete and `[ ]` for incomplete states.

#### Scenario: Checklist uses stable ordered rendering
- **WHEN** scanner runs multiple times with unchanged repository state
- **THEN** `overmind/step_state.md` content SHALL be byte-identical across runs

#### Scenario: Checklist line format is canonical
- **WHEN** any step is rendered
- **THEN** each step line SHALL use exactly one checkbox marker (`[x]` or `[ ]`) and include step number and step name

### Requirement: Scanner SHALL append canonical next-step line
`overmind/step_state.md` SHALL end with `next step: <number> (<name>)` for the first incomplete step after the last contiguous completed steps, or `next step: none` when all steps are complete.

#### Scenario: Incomplete steps remain
- **WHEN** at least one step is incomplete
- **THEN** the final line SHALL name the next sequential incomplete step as `next step: <number> (<name>)`

#### Scenario: All steps complete
- **WHEN** all defined steps are complete
- **THEN** the final line SHALL be exactly `next step: none`

### Requirement: Bootstrap checklist contract SHALL include template, golden example, and tests
The repository SHALL include a template and a golden example for `overmind/step_state.md`, and scanner behavior SHALL be covered by tests in `tests/ai_scripts/`.

#### Scenario: Contract artifacts exist for checklist output
- **WHEN** a contributor needs output format guidance
- **THEN** template and golden example files for `overmind/step_state.md` SHALL be present under `overmind/templates/` and `overmind/golden_examples/`

#### Scenario: Script tests validate scanner behavior
- **WHEN** scanner regression tests execute from repository root
- **THEN** tests SHALL verify checklist rendering, `next step` calculation, default-folder lookup, `special_folder` override behavior, and optional `check_key_value` gating

### Requirement: Scanner SHALL short-circuit checklist evaluation after the first incomplete step
The scanner SHALL evaluate checklist steps in declared order and SHALL stop running artifact/content checks for subsequent steps once the first incomplete step is found.

#### Scenario: Step 2 incomplete prevents Step 3 evaluation
- **WHEN** Step 2 requirements are not satisfied
- **THEN** Step 3 and later steps SHALL be rendered as `[ ]` without evaluating their artifact checks, even when a Step 3 EARS artifact exists at the selected feature root

#### Scenario: Step 1 incomplete prevents all later evaluation
- **WHEN** Step 1 requirements are not satisfied
- **THEN** Step 2 and all later steps SHALL remain `[ ]` and SHALL NOT execute their completion checks

### Requirement: Bootstrap Step 3 SHALL use overmind EARS artifact path
The bootstrap definition for Step 3 (`Convert Business Requirements Structuring to EARS`) SHALL require `requirements_ears_feature.md` using product-root checklist resolution (`special_folder: /overmind/product`) so completion is evaluated at the active feature root.

#### Scenario: Step 3 marked complete when default feature-root EARS artifact exists and prefix is complete
- **WHEN** Steps 1 and 2 are complete and `overmind/product/requirements_ears_feature.md` exists
- **THEN** Step 3 SHALL be rendered as `[x]`

#### Scenario: Step 3 marked complete when override feature-root EARS artifact exists and prefix is complete
- **WHEN** Steps 1 and 2 are complete, scanner runs with `--feature_path overmind/product/custom-folder`, and `overmind/product/custom-folder/requirements_ears_feature.md` exists
- **THEN** Step 3 SHALL be rendered as `[x]`

#### Scenario: Step 3 remains incomplete when feature-root EARS artifact is missing
- **WHEN** Steps 1 and 2 are complete and `requirements_ears_feature.md` does not exist under the active feature root
- **THEN** Step 3 SHALL be rendered as `[ ]`

### Requirement: Scanner SHALL mirror rendered checklist output to stdout
For every successful scan run that renders checklist state, the scanner SHALL emit the same rendered checklist payload to terminal stdout while continuing to persist that payload to `overmind/step_state.md`.

#### Scenario: Terminal output mirrors persisted checklist exactly
- **WHEN** `overmind/scripts/init_progress_scanner.sh` completes checklist rendering
- **THEN** stdout SHALL contain the full checklist payload
- **AND** the emitted stdout checklist payload SHALL be byte-identical to the content written to `overmind/step_state.md`

#### Scenario: Mirrored output includes canonical next-step line
- **WHEN** the scanner renders checklist state
- **THEN** stdout SHALL include the same final `next step` line that is persisted in `overmind/step_state.md`

### Requirement: Progress scanner SHALL support invocation-scoped product-root override
`overmind/scripts/init_progress_scanner.sh` SHALL accept optional `--feature_path <path>` and SHALL apply it only for product-root checklist target resolution during that invocation.

#### Scenario: Scanner uses default product root when override is omitted
- **WHEN** scanner runs without `--feature_path`
- **THEN** checklist entries that target product root SHALL resolve using `overmind/product`

#### Scenario: Scanner uses selected product root when override is provided
- **WHEN** scanner runs with `--feature_path overmind/product/custom-folder`
- **THEN** checklist entries that target product root SHALL resolve using `overmind/product/custom-folder`

#### Scenario: Scanner keeps non-product path behavior unchanged
- **WHEN** scanner runs with `--feature_path <path>` and evaluates checklist entries that target non-product locations
- **THEN** scanner SHALL preserve existing default-root and `special_folder` semantics for those entries

#### Scenario: Scanner override is stateless across invocations
- **WHEN** scanner runs once with `--feature_path <path>` and then runs again without that flag
- **THEN** the second run SHALL resolve product-root checklist targets using default `overmind/product`

### Requirement: Scanner SHALL support `exactly_one` artifact-group mode
For each entry in `finished_only_if_artefact_groups`, scanner completion SHALL evaluate the declared `mode`. For `mode: exactly_one`, a group SHALL be complete only when exactly one group entry matches; zero or more than one matches SHALL fail the group.

#### Scenario: Exactly one group entry matches
- **WHEN** a group with `mode: exactly_one` has exactly one matching artifact entry
- **THEN** that group SHALL be marked complete

#### Scenario: No group entries match
- **WHEN** a group with `mode: exactly_one` has zero matching artifact entries
- **THEN** that group SHALL be marked incomplete

#### Scenario: Multiple group entries match
- **WHEN** a group with `mode: exactly_one` has more than one matching artifact entry
- **THEN** that group SHALL be marked incomplete

### Requirement: Bootstrap Step 4 SHALL enforce exclusive technical summary artifacts
Step 4 (`Prepare Technical Baseline Documents`) SHALL keep `repo_structure_summary.md` and `contracts_inventory.md` as required artifacts and SHALL enforce technical summary exclusivity through one `finished_only_if_artefact_groups` entry with `mode: exactly_one` containing `project_tech_summary_be.md` and `project_tech_summary_fe.md` under product-root resolution.

#### Scenario: Step 4 complete with backend-only technical summary
- **WHEN** prior steps are complete, required Step-4 baseline artifacts exist, and only `project_tech_summary_be.md` exists in the selected feature root
- **THEN** Step 4 SHALL be rendered as `[x]`

#### Scenario: Step 4 incomplete when both technical summaries exist
- **WHEN** prior steps are complete, required Step-4 baseline artifacts exist, and both `project_tech_summary_be.md` and `project_tech_summary_fe.md` exist in the selected feature root
- **THEN** Step 4 SHALL be rendered as `[ ]`

#### Scenario: Step 4 incomplete when neither technical summary exists
- **WHEN** prior steps are complete, required Step-4 baseline artifacts exist, and neither technical summary exists in the selected feature root
- **THEN** Step 4 SHALL be rendered as `[ ]`

