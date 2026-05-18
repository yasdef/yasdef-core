## ADDED Requirements

### Requirement: Startup proceed-or-change prompt when valid current feature exists
When the orchestrator starts in default mode without `--resume` and `.asdlc_worker/feature_meta_sync.yaml` passes reuse validation AND plan analysis returns a non-empty `first_unchecked` (i.e., the feature is valid and runnable, and crp-124's blocked/exhausted fail-fast gates do not apply), the orchestrator SHALL prompt the operator with two options: `1. Proceed with current feature` and `2. Change feature`. The orchestrator SHALL wait for the operator to choose before continuing.

#### Scenario: Operator chooses proceed with current feature
- **WHEN** the orchestrator detects a valid runnable current feature at startup and the operator selects option 1 (Proceed)
- **THEN** the orchestrator continues with the current feature and step without running slow-path discovery

#### Scenario: Operator chooses change feature
- **WHEN** the orchestrator detects a valid runnable current feature at startup and the operator selects option 2 (Change feature)
- **THEN** the orchestrator runs the slow-path candidate discovery flow
- **THEN** the prior current feature ID is propagated to the picker via `CURRENT_FEATURE_SWITCH_FROM_ID`
- **THEN** the newly selected feature is written to `.asdlc_worker/feature_meta_sync.yaml` after the picker returns

#### Scenario: Invalid input at startup prompt loops until valid
- **WHEN** the operator enters a value other than 1 or 2 at the proceed-or-change prompt
- **THEN** the orchestrator displays an error and re-prompts until a valid selection is received

### Requirement: Non-interactive startup skips the prompt and proceeds
When stdin is not a TTY, the orchestrator SHALL skip the proceed-or-change prompt and treat the outcome as "Proceed with current feature".

#### Scenario: Non-interactive startup auto-proceeds
- **WHEN** the orchestrator detects a valid runnable current feature at startup and stdin is not a TTY
- **THEN** the orchestrator proceeds with the current feature without displaying the proceed-or-change prompt

### Requirement: No startup prompt for resume or standalone mode
The proceed-or-change prompt SHALL NOT be shown during `--resume` invocations or `--standalone` mode runs.

#### Scenario: Resume skips startup prompt
- **WHEN** the operator invokes the orchestrator with `--resume`
- **THEN** no proceed-or-change prompt is displayed
- **THEN** the orchestrator reuses the current feature directly if valid (per sticky-current-feature-routing rules from crp-124)

#### Scenario: Standalone mode skips startup prompt
- **WHEN** the orchestrator runs in standalone mode
- **THEN** no proceed-or-change prompt is displayed

### Requirement: No startup prompt when no valid runnable current feature exists
The proceed-or-change prompt SHALL only appear when a valid runnable current feature has been confirmed. If `.asdlc_worker/feature_meta_sync.yaml` is absent, fails reuse validation, or the stored feature is blocked/exhausted (crp-124 fail-fast paths), the orchestrator SHALL NOT display the prompt.

#### Scenario: No feature_meta_sync.yaml skips startup prompt
- **WHEN** no `.asdlc_worker/feature_meta_sync.yaml` exists
- **THEN** no proceed-or-change prompt is displayed and slow-path discovery runs as normal

#### Scenario: Stale feature_meta_sync.yaml skips startup prompt
- **WHEN** `.asdlc_worker/feature_meta_sync.yaml` exists but fails reuse validation (identity mismatch or missing bound-source paths)
- **THEN** no proceed-or-change prompt is displayed and slow-path discovery runs as normal

#### Scenario: Blocked or exhausted feature does not reach the startup prompt
- **WHEN** `.asdlc_worker/feature_meta_sync.yaml` passes reuse validation but the stored feature is blocked or exhausted
- **THEN** the orchestrator fails fast per crp-124 before any prompt is displayed

### Requirement: Current feature appears first and labeled in the feature picker after change
When the operator chooses `Change feature` and slow-path discovery produces a candidate list that includes the prior current feature (by ID matching `CURRENT_FEATURE_SWITCH_FROM_ID`), the prior current feature SHALL be placed at index 0 in the list and its display name SHALL include a `(CURRENT)` label.

#### Scenario: Current feature found in candidate list appears first
- **WHEN** the operator chooses Change feature and slow-path discovery finds a candidate whose ID matches `CURRENT_FEATURE_SWITCH_FROM_ID`
- **THEN** that candidate is listed first in the feature picker with `(CURRENT)` appended to its name

#### Scenario: Current feature not found in candidate list after change
- **WHEN** the operator chooses Change feature and slow-path discovery produces a candidate list that does not include the prior current feature ID
- **THEN** the feature picker displays normally without a `(CURRENT)` entry

#### Scenario: Single-candidate discovery auto-selects without prompting
- **WHEN** the operator chooses Change feature and slow-path discovery surfaces exactly one candidate
- **THEN** the orchestrator auto-selects that candidate without displaying the picker prompt
- **THEN** the `(CURRENT)` relabel is still applied in any log output that lists the candidate
