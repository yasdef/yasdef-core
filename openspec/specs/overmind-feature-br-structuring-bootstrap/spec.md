## Purpose
Define deterministic BR-structuring bootstrap behavior, skeleton output contract, and phase-1 handoff boundaries.
## Requirements
### Requirement: BRS initializer SHALL capture project type via strict numeric chooser
`overmind/scripts/init_br_scaffold.sh` SHALL request project type with a `choose: 1/2/3` prompt and SHALL map selections to project types `A`, `B`, and `C` respectively.

#### Scenario: Valid project type selection is persisted
- **WHEN** a user selects `1`, `2`, or `3`
- **THEN** the initializer SHALL write the mapped project type code and meaning into the resolved BR summary file under `/overmind/product/tmp*/feature_br_summary.md`

#### Scenario: Invalid project type selection is rejected
- **WHEN** user input is not one of `1`, `2`, or `3`
- **THEN** the initializer SHALL display validation guidance and SHALL continue prompting until a valid choice is entered

### Requirement: Initializer SHALL generate deterministic, unfilled BRS skeleton
`overmind/scripts/init_br_scaffold.sh` SHALL create BR summary output under `/overmind/product/tmp*/feature_br_summary.md` using a fixed ordered structure and deterministic placeholder content, and SHALL encode sections `## 6. Functional Requirements` and `## 7. Business Rules and Decision Logic` as one-line `FR-N` and `BR-N` line-item placeholders with open-ended cardinality.

#### Scenario: Skeleton is created with canonical section order
- **WHEN** the initializer runs successfully
- **THEN** the resolved `/overmind/product/tmp*/feature_br_summary.md` SHALL contain the canonical ordered BRS structure defined by template, including one-line FR/BR line-item sections

#### Scenario: Epic/Story prefill is not performed in bootstrap step
- **WHEN** the initializer creates the initial BRS document
- **THEN** business-detail fields SHALL remain explicitly unfilled with canonical placeholders for later enrichment

### Requirement: BRS template and golden example SHALL be maintained
The repository SHALL include `overmind/templates/feature_br_summary_TEMPLATE.md` and `overmind/golden_examples/feature_br_summary_GOLDEN_EXAMPLE.md` aligned to the same canonical structure as generated output, including one-line `FR-N` and `BR-N` sections with explicit open-ended cardinality guidance.

#### Scenario: Contributors need canonical structure guidance
- **WHEN** a contributor prepares or reviews BRS initialization artifacts
- **THEN** template and golden example files SHALL both exist and SHALL reflect the fixed ordered BRS format with one-line FR/BR line-item structure

#### Scenario: Golden example avoids fixed two-item implication
- **WHEN** contributors use the golden example to infer expected FR/BR shape
- **THEN** the example SHALL demonstrate more than two FR and BR items to avoid implying a two-item maximum

### Requirement: Initializer behavior SHALL be regression-tested under canonical script tests location
Tests for BRS initialization SHALL exist under `tests/ai_scripts/` and SHALL validate type selection mapping, tmp-workspace output path selection, deterministic structure, skeleton-only behavior, and one-line FR/BR section contract.

#### Scenario: Script tests execute from repository root
- **WHEN** the BRS initializer and related helper suites run
- **THEN** they SHALL verify `choose: 1/2/3` interaction handling, A/B/C persistence, deterministic `tmp/tmpN` output targeting, deterministic skeleton output, no Epic/Story prefill, and one-line FR/BR contract expectations

### Requirement: Repo-scan initializer SHALL gate by project type before model execution
`overmind/scripts/init_scan_repo_for_br.sh` SHALL read `project_type_code` from the active BR summary file resolved from `overmind/product/tmp*/feature_br_summary.md`, with fallback to `overmind/product/feature_br_summary.md`, and SHALL stop with deterministic non-zero failures for unsupported contexts.

#### Scenario: Project type cannot be determined
- **WHEN** no active BR summary file can be resolved or `project_type_code` is missing/undetectable in the resolved file
- **THEN** the script SHALL exit non-zero and output exactly `unable to defile project type`

#### Scenario: New-project type is not eligible for repo scan
- **WHEN** `project_type_code` is `A` in the resolved active BR summary file
- **THEN** the script SHALL exit non-zero and output exactly `for new projects repo scan not applicable`

### Requirement: Repo-scan initializer SHALL invoke Codex from `repo_analyse` model contract
For non-`A` project types, `overmind/scripts/init_scan_repo_for_br.sh` SHALL load command/model/args from `overmind/setup/models.md` row `repo_analyse` and SHALL execute Codex using that configuration.

#### Scenario: Non-new project runs model with configured arguments
- **WHEN** `project_type_code` is not `A` and `repo_analyse` is configured
- **THEN** the script SHALL execute Codex with configured model and extra args from `overmind/setup/models.md`

#### Scenario: Model prompt references repo-scan rules and target artifact
- **WHEN** Codex invocation is prepared
- **THEN** prompt context SHALL reference `overmind/rules/repo_br_scan_rule.md` and require updates to the resolved active BR summary file path

### Requirement: Repo-scan enrichment rules SHALL be versioned as durable rule artifact
The repository SHALL include `overmind/rules/repo_br_scan_rule.md` defining deterministic BR repo-scan enrichment constraints consumed by the initializer.

#### Scenario: Rule artifact exists and is consumed by initializer
- **WHEN** `overmind/scripts/init_scan_repo_for_br.sh` runs for eligible project types
- **THEN** it SHALL load and pass rule guidance from `overmind/rules/repo_br_scan_rule.md` into model invocation context

### Requirement: Repo-scan initializer behavior SHALL be regression-tested
Script tests for repo-scan BR enrichment SHALL exist under `tests/ai_scripts/` and SHALL validate fail-fast gates and non-`A` model invocation behavior.

#### Scenario: Test suite covers required gating and invocation paths
- **WHEN** `tests/ai_scripts/init_scan_repo_for_br_tests.sh` runs from repository root
- **THEN** it SHALL verify undefined type failure, `A`-type failure, and successful non-`A` execution with configured model arguments and rule-aware prompt context

### Requirement: User-input completeness gate SHALL require at least one populated BR item
The task-to-BR quality gate SHALL fail unless `## 7. Business Rules and Decision Logic` contains at least one meaningful populated one-line item matching `- BR-N: ...`.

#### Scenario: BR section contains at least one populated one-line item
- **WHEN** `feature_br_summary.md` includes at least one `BR-[0-9]+` item with non-`[UNFILLED]` value
- **THEN** BR-count validation in `check_task_to_br_quality.sh` SHALL pass

#### Scenario: BR section has no populated one-line BR items
- **WHEN** all `BR-[0-9]+` items are missing, empty, or `[UNFILLED]`
- **THEN** `check_task_to_br_quality.sh` SHALL exit non-zero and report a deterministic missing BR-item error

### Requirement: Open-question and scope-boundary unresolved items SHALL be externalized from BR
The task-to-BR stage SHALL NOT keep unresolved non-`rised` entries in `## 15. Open Questions` or `### 5.3 Open scope boundaries` (`unclear_scope_points`) after a gate-failure processing cycle.

#### Scenario: Non-`rised` unresolved open-question entries are present
- **WHEN** `## 15. Open Questions` includes unresolved entries without `rised` marking
- **THEN** the stage SHALL move those entries into `overmind/product/missing_br_data.md` and remove unresolved non-`rised` copies from BR

#### Scenario: Non-`rised` unresolved unclear-scope points are present
- **WHEN** `### 5.3 Open scope boundaries` contains `unclear_scope_points` unresolved entries without `rised` marking
- **THEN** the stage SHALL move those entries into `overmind/product/missing_br_data.md` and remove unresolved non-`rised` copies from BR

### Requirement: Missing-data tracking SHALL use deterministic `rised` marker format
Any unresolved business item moved from BR into `overmind/product/missing_br_data.md` SHALL be marked with deterministic `rised` format so follow-up lifecycle is auditable.

#### Scenario: Moved unresolved items are written to missing-data artifact
- **WHEN** unresolved entries are externalized from BR sections
- **THEN** each moved item in `missing_br_data.md` SHALL include explicit `rised` marking using the canonical format defined by rule/template artifacts

### Requirement: Rule and examples SHALL encode move-and-mark contract
`overmind/rules/task_to_br_rule.md`, `overmind/templates/missing_br_data_TEMPLATE.md`, and `overmind/golden_examples/missing_br_data_GOLDEN_EXAMPLE.md` SHALL explicitly define the unresolved-item move-and-mark behavior and canonical `rised` notation.

#### Scenario: Contributors follow user-input enrichment contract
- **WHEN** the task-to-BR phase prepares or reviews missing-data behavior
- **THEN** rule, template, and golden-example artifacts SHALL describe identical deterministic handling for BR-item move and `rised` marking

### Requirement: Script tests SHALL cover BR-count and unresolved-item hygiene gates
Regression tests under `tests/ai_scripts/` SHALL validate BR-count failure, non-`rised` open-question handling, non-`rised` unclear-scope-point handling, and required `rised` marker output in missing-data tracking.

#### Scenario: Script suites execute from repository root
- **WHEN** task-to-BR helper and stage tests run
- **THEN** they SHALL include assertions for all new hardening checks and deterministic `rised` formatting

### Requirement: Phase-1 user-input rule SHALL be scoped to extraction and uncertainty externalization
`overmind/rules/task_to_br_rule.md` SHALL define only phase-1 responsibilities: business-data extraction from user/story input, helper-driven BR completeness checks, and uncertainty externalization into `overmind/product/missing_br_data.md`.

#### Scenario: Phase-1 rules exclude phase-2 ownership
- **WHEN** `overmind/rules/task_to_br_rule.md` is used by `overmind/scripts/init_task_to_br.sh`
- **THEN** it SHALL not be the authoritative contract for full unresolved missing-data user loop closure

### Requirement: User-input initializer SHALL hand off unresolved missing-data work to dedicated phase-2 flow
`overmind/scripts/init_task_to_br.sh` SHALL keep phase-1 behavior and SHALL hand off unresolved `missing_br_data.md` processing to the dedicated phase-2 script and rule path.

#### Scenario: Phase-1 completes with unresolved missing-data artifacts
- **WHEN** `overmind/product/missing_br_data.md` contains unresolved items after phase-1 processing
- **THEN** `init_task_to_br.sh` SHALL not claim final loop closure and SHALL hand off to the dedicated phase-2 user BR clarification step

#### Scenario: Phase-1 completes without unresolved missing-data artifacts
- **WHEN** no unresolved missing-data work remains after phase-1 processing
- **THEN** handoff to phase-2 SHALL be skipped and phase-1 may finish normally

