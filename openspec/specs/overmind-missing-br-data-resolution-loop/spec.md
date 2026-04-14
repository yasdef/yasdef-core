## Purpose
Define the dedicated phase-2 unresolved missing-data resolution loop, separate from phase-1 user-input extraction.
## Requirements
### Requirement: Phase-2 missing-data loop rule SHALL be defined separately
The repository SHALL include `overmind/rules/user_br_clarification_rule.md` as the authoritative contract for unresolved `missing_br_data.md` AI-user clarification behavior, separate from phase-1 extraction rules.

#### Scenario: Dedicated phase-2 rule artifact exists
- **WHEN** contributors implement or review unresolved phase-2 clarification behavior
- **THEN** `overmind/rules/user_br_clarification_rule.md` SHALL exist and SHALL define loop behavior independent from `overmind/rules/task_to_br_rule.md`

### Requirement: Dedicated phase-2 script step SHALL gate on unresolved missing-data state
A dedicated script step, `overmind/scripts/init_user_br_clarification.sh`, SHALL first check whether `overmind/product/missing_br_data.md` exists, then check unresolved items state, and SHALL invoke model workflow only when phase-2 clarification is required.

#### Scenario: Missing-data artifact absent
- **WHEN** `overmind/product/missing_br_data.md` does not exist
- **THEN** the phase-2 script SHALL exit successfully without invoking model loop processing

#### Scenario: Missing-data artifact has unresolved items
- **WHEN** `overmind/product/missing_br_data.md` exists and unresolved loop items are present
- **THEN** the phase-2 script SHALL invoke model processing with `overmind/rules/user_br_clarification_rule.md`

### Requirement: Phase-2 model loop SHALL be user-involved and helper-verified
When unresolved missing-data items exist, model workflow SHALL ask targeted business-only user questions, keep question-state tracking in `overmind/product/missing_br_data.md` (`rised` markers), write actual answer content only in `overmind/product/feature_br_summary.md`, and rerun helper checks after each answer round.

#### Scenario: Helper still reports unresolved loop state
- **WHEN** helper output indicates unresolved phase-2 clarification items remain
- **THEN** model SHALL continue user-involved business-only follow-up rounds and SHALL NOT declare phase complete

#### Scenario: Helper confirms closure
- **WHEN** helper checks pass and unresolved loop state is closed
- **THEN** model SHALL conclude phase-2 clarification processing as complete

### Requirement: Phase-2 regression tests SHALL prevent premature completion
Regression tests under `tests/ai_scripts/` SHALL cover phase-2 invocation gating and unresolved-loop completion semantics.

#### Scenario: Unresolved loop state prevents premature finish
- **WHEN** unresolved items remain in `overmind/product/missing_br_data.md`
- **THEN** tests for `init_user_br_clarification.sh` SHALL verify workflow does not report completion before user-loop processing is executed

