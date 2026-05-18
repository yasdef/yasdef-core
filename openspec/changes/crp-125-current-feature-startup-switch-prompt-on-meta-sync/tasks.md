## 1. Orchestrator global state

- [x] 1.1 Add `CURRENT_FEATURE_SWITCH_FROM_ID=""` to the global state variable declarations in `ai/scripts/orchestrator.sh`

## 2. Startup prompt in fast path

- [x] 2.1 In `_try_fast_path_feature_context` (post-crp-123/124), after the branch that sets `SELECTED_STEP="$_fu"` for a valid runnable feature, add a guard: if `resume_mode == 1`, `STANDALONE_MODE == 1`, or stdin is not a TTY, skip the prompt and return 0 as today
- [x] 2.2 When the prompt condition is met, display the two-option menu (`1. Proceed with current feature` / `2. Change feature`) to stderr and read the operator's choice in a validation loop
- [x] 2.3 If the operator chooses option 1 (Proceed), continue with the current feature as before and return 0
- [x] 2.4 If the operator chooses option 2 (Change feature), set `CURRENT_FEATURE_SWITCH_FROM_ID="$SELECTED_FEATURE_ID"`, reset the reuse-populated state variables (`SELECTED_FEATURE_ID`, `SELECTED_FEATURE_PATH`, `SELECTED_STEP`, `IMPLEMENTATION_PLAN_FILE`), and return 1 so the caller runs slow-path discovery
- [x] 2.5 Confirm the prompt is placed AFTER crp-124's `_fu`-empty fail-fast branches so blocked/exhausted features never reach the prompt

## 3. Feature picker CURRENT label

- [x] 3.1 In `prompt_for_feature_selection_index`, before building the display list, check if `CURRENT_FEATURE_SWITCH_FROM_ID` is non-empty and find its index in the candidate `feature_ids` array
- [x] 3.2 If found, move the matching feature ID to index 0 of the display list and append ` (CURRENT)` to its displayed name
- [x] 3.3 Ensure the returned index from the picker maps correctly back to the original `candidate_*` arrays in `ensure_feature_runtime_context` after the reorder
- [x] 3.4 Confirm single-candidate auto-select still works when `CURRENT_FEATURE_SWITCH_FROM_ID` matches the lone candidate

## 4. Clear switch-from signal after discovery

- [x] 4.1 In `ensure_feature_runtime_context`, clear `CURRENT_FEATURE_SWITCH_FROM_ID` after slow-path discovery completes (regardless of which feature was picked) so it does not leak into any subsequent code paths within the same invocation

## 5. Test updates — assignment tests

- [x] 5.1 Add a test in `tests/ai_scripts/orchestrator_assignment_tests.sh` for the interactive proceed case: valid runnable current feature, operator enters `1` → reuses current feature without slow-path discovery
- [x] 5.2 Add a test for the interactive change case: valid runnable current feature, operator enters `2` → runs slow-path discovery, current feature appears first with `(CURRENT)` label, picker selection overwrites `feature_meta_sync.yaml`
- [x] 5.3 Add a test for non-interactive skip: valid runnable current feature, stdin is not a TTY → auto-proceeds without prompt
- [x] 5.4 Add a test that resume mode skips the startup prompt even when a valid runnable current feature exists
- [ ] 5.5 Add a test that standalone mode skips the startup prompt (N/A: standalone mode was removed in commit f04d3a4; no STANDALONE_MODE variable exists in the codebase)
- [x] 5.6 Add a test that the blocked-feature fail-fast (crp-124) runs without ever displaying the prompt
- [x] 5.7 Add a test that the exhausted-feature fail-fast (crp-124) runs without ever displaying the prompt
- [x] 5.8 Update any existing tests that assumed the fast path always proceeds silently when a valid current feature is found, to account for the new prompt (no updates needed: all existing fast-path tests either use --resume or run non-interactively, so the -t 0 guard prevents the prompt from appearing)

## 6. Test updates — picker behavior

- [x] 6.1 Add a test where `CURRENT_FEATURE_SWITCH_FROM_ID` matches one of multiple candidates: that candidate appears first with `(CURRENT)` and the picker reorder maps correctly back to original arrays
- [x] 6.2 Add a test where `CURRENT_FEATURE_SWITCH_FROM_ID` does not match any candidate (stale ID): the picker displays normally without a `(CURRENT)` entry
- [x] 6.3 Add a test for single-candidate auto-select when `CURRENT_FEATURE_SWITCH_FROM_ID` matches the lone candidate

## 7. State persistence verification

- [x] 7.1 Add an assertion in an existing or new test that `feature_meta_sync.yaml` after Change-feature flow contains exactly the four fields specified by crp-123 (no leaked routing-signal field)

## 8. Documentation

- [x] 8.1 Update `Readme.md` operator-facing documentation to describe the proceed-or-change startup prompt, its non-interactive behavior, and its interaction with crp-124's sticky/fail-fast semantics

## 9. Close superseded change

- [x] 9.1 After crp-125 is filed, close `crp-119-current-feature-startup-switch-prompt` (rename with `_CLOSED` suffix following the established convention) and leave a one-line note pointing at crp-125

