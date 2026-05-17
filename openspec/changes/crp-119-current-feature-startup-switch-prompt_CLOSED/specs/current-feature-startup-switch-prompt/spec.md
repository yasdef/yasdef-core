## ADDED Requirements

### Requirement: Startup proceed-or-change prompt when valid current feature exists
When the orchestrator starts in non-standalone, non-resume mode and a valid current feature with a runnable step is detected, the orchestrator SHALL prompt the operator with two options: `1. Proceed with current feature` and `2. Change feature`. The orchestrator SHALL wait for the operator to choose before continuing.

#### Scenario: Operator chooses proceed with current feature
- **WHEN** the orchestrator detects a valid current feature at startup and the operator selects option 1 (Proceed)
- **THEN** the orchestrator continues with the current feature and step without running global discovery

#### Scenario: Operator chooses change feature
- **WHEN** the orchestrator detects a valid current feature at startup and the operator selects option 2 (Change feature)
- **THEN** the orchestrator runs the normal global candidate discovery flow
- **THEN** the current feature is placed first in the candidate list and labeled `(CURRENT)`

#### Scenario: Invalid input at startup prompt loops until valid
- **WHEN** the operator enters a value other than 1 or 2 at the proceed-or-change prompt
- **THEN** the orchestrator displays an error and re-prompts until a valid selection is received

### Requirement: Non-interactive startup skips the prompt and proceeds
When stdin is not a TTY, the orchestrator SHALL skip the proceed-or-change prompt and treat the outcome as "Proceed with current feature".

#### Scenario: Non-interactive startup auto-proceeds
- **WHEN** the orchestrator detects a valid current feature at startup and stdin is not a TTY
- **THEN** the orchestrator proceeds with the current feature without displaying the proceed-or-change prompt

### Requirement: No startup prompt for resume or standalone mode
The proceed-or-change prompt SHALL NOT be shown during `--resume` invocations or `--standalone` mode runs.

#### Scenario: Resume skips startup prompt
- **WHEN** the operator invokes the orchestrator with `--resume`
- **THEN** no proceed-or-change prompt is displayed
- **THEN** the orchestrator reuses the current feature directly if valid (per sticky-current-feature-routing rules)

#### Scenario: Standalone mode skips startup prompt
- **WHEN** the orchestrator runs in standalone mode
- **THEN** no proceed-or-change prompt is displayed

### Requirement: No startup prompt when no valid current feature exists
The proceed-or-change prompt SHALL only appear when a valid current feature has been confirmed. If `feature_sync.yaml` is absent or fails reuse validation, the orchestrator SHALL skip the prompt and run global discovery directly.

#### Scenario: No feature_sync.yaml skips startup prompt
- **WHEN** no `feature_sync.yaml` exists
- **THEN** no proceed-or-change prompt is displayed and global discovery runs as normal

#### Scenario: Stale feature_sync.yaml skips startup prompt
- **WHEN** `feature_sync.yaml` exists but fails reuse validation
- **THEN** no proceed-or-change prompt is displayed and global discovery runs as normal

### Requirement: Current feature appears first and labeled in the feature picker after change
When the operator chooses `Change feature` and global discovery produces a candidate list that includes the current feature (by ID), the current feature SHALL be placed at index 0 in the list and its display name SHALL include a `(CURRENT)` label.

#### Scenario: Current feature found in candidate list appears first
- **WHEN** the operator chooses Change feature and global discovery finds a candidate whose ID matches the current feature
- **THEN** that candidate is listed first in the feature picker with `(CURRENT)` appended to its name

#### Scenario: Current feature not found in candidate list after change
- **WHEN** the operator chooses Change feature and global discovery produces a candidate list that does not include the current feature ID
- **THEN** the feature picker displays normally without a `(CURRENT)` entry
