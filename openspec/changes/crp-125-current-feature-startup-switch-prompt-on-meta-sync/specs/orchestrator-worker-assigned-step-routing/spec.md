## ADDED Requirements

### Requirement: Interactive feature selection includes explicit current-feature handoff path
When the operator chooses `Change feature` at the startup prompt and slow-path discovery surfaces multiple candidates, the feature picker SHALL place the candidate whose ID matches `CURRENT_FEATURE_SWITCH_FROM_ID` at position 1 (first) in the list with a `(CURRENT)` label. The operator SHALL then select from the full candidate list, including the relabeled current feature.

#### Scenario: Feature picker places current feature first with label
- **WHEN** slow-path discovery finds multiple candidate features and one of them matches the feature ID the operator chose to switch away from
- **THEN** that feature is listed first in the picker and its display name includes `(CURRENT)`
- **THEN** all other candidates follow in their normal discovery order

#### Scenario: Feature picker shows normally when prior current feature is not a candidate
- **WHEN** slow-path discovery produces a candidate list that does not include the prior current feature ID
- **THEN** the feature picker displays candidates in normal discovery order without any `(CURRENT)` label

#### Scenario: Auto-selection when only one candidate exists after change
- **WHEN** the operator chooses Change feature and slow-path discovery finds exactly one candidate
- **THEN** the orchestrator auto-selects that single candidate without prompting

### Requirement: CURRENT_FEATURE_SWITCH_FROM_ID does not persist across orchestrator runs
The `CURRENT_FEATURE_SWITCH_FROM_ID` signal SHALL be a process-local variable cleared on each orchestrator startup. It MUST NOT be persisted to disk or to `.asdlc_worker/feature_meta_sync.yaml`.

#### Scenario: Fresh orchestrator run starts with empty switch-from signal
- **WHEN** the orchestrator process starts
- **THEN** `CURRENT_FEATURE_SWITCH_FROM_ID` is empty before any prompt or discovery runs

#### Scenario: Switch-from signal does not appear in feature_meta_sync.yaml
- **WHEN** the orchestrator writes `.asdlc_worker/feature_meta_sync.yaml` after a successful feature selection
- **THEN** the file contains exactly the four fields specified by crp-123 (`project_id`, `worker_uuid`, `feature_id`, `selected_step`)
- **THEN** the file does not contain `CURRENT_FEATURE_SWITCH_FROM_ID` or any related routing-signal field
