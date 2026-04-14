## Purpose
Define the model-owned business-context gate recovery loop for task-to-BR and the thin-shell boundary around the initializer.
## Requirements
### Requirement: User-input enrichment rule SHALL define a model-owned gate-recovery loop contract
`overmind/rules/task_to_br_rule.md` SHALL define one explicit model-owned Business Context Completeness Gate recovery loop contract for task-to-BR.

#### Scenario: Rule file is consumed for user-input enrichment
- **WHEN** the model follows `overmind/rules/task_to_br_rule.md` during `init_task_to_br.sh` flow
- **THEN** the contract SHALL require the loop to start from helper output and continue until gate pass or no additional usable business answers

### Requirement: Loop rounds SHALL be driven by helper output and targeted business follow-ups
Each loop round SHALL run `overmind/scripts/helper/check_task_to_br_quality.sh overmind/product/feature_br_summary.md`; on gate failure with unresolved items, the model SHALL ask targeted business follow-up questions for those unresolved items only.

#### Scenario: Gate fails with unresolved items
- **WHEN** helper exit code is `1` and unresolved items are reported
- **THEN** the model SHALL ask business-domain follow-up questions mapped to the unresolved items and SHALL avoid technical implementation questions

### Requirement: Model SHALL update BR and missing-data artifacts after each answer round
After each user-backed answer batch, the model SHALL update `overmind/product/feature_br_summary.md`, mark resolved items explicitly in `overmind/product/missing_br_data.md`, and rerun the helper gate.

#### Scenario: User provides usable follow-up answers
- **WHEN** the user provides additional business answers for unresolved items
- **THEN** the model SHALL apply those answers, record explicit resolved markers in `missing_br_data.md`, and rerun the helper before deciding completion

### Requirement: Missing-data artifact SHALL keep deterministic unresolved and resolved markers
`overmind/templates/missing_br_data_TEMPLATE.md` and `overmind/golden_examples/missing_br_data_GOLDEN_EXAMPLE.md` SHALL define deterministic marker formats for moved unresolved entries (`rised_item_N`) and explicit resolved entries (`resolved_item_N`).

#### Scenario: Missing-data artifact is generated or refreshed
- **WHEN** gate failure handling updates `overmind/product/missing_br_data.md`
- **THEN** entries SHALL follow deterministic marker formats for both unresolved rised items and resolved items

### Requirement: Loop termination SHALL preserve unresolved state when gate does not pass
If the user provides no additional usable business answers and the gate still fails, unresolved items SHALL remain clearly marked in `overmind/product/missing_br_data.md`.

#### Scenario: User cannot provide further usable answers
- **WHEN** helper continues failing after a follow-up round and the user provides no new usable business input
- **THEN** the model SHALL keep unresolved items clearly marked and report what remains unresolved

### Requirement: User-input initializer SHALL NOT orchestrate gate-recovery loop flow
`overmind/scripts/init_task_to_br.sh` SHALL only capture input, invoke the model, and commit generated artifacts; it SHALL NOT orchestrate helper-processing loop flow, missing-data reconciliation, or per-question control flow.

#### Scenario: Initializer executes user-input enrichment phase
- **WHEN** `overmind/scripts/init_task_to_br.sh` builds and runs the model prompt
- **THEN** it SHALL pass concise authoritative context and SHALL leave gate-recovery loop control to the model rule contract

### Requirement: Script tests SHALL enforce model-loop expectations and thin-shell boundaries
`tests/ai_scripts/init_task_to_br_tests.sh` SHALL cover model-owned loop expectations and verify shell initializer behavior remains thin.

#### Scenario: User-input initializer tests run from repository root
- **WHEN** `bash tests/ai_scripts/init_task_to_br_tests.sh` is executed
- **THEN** tests SHALL detect regressions where loop or reconciliation logic moves into shell or deterministic marker expectations drift

