## 1. Orchestrator global state

- [ ] 1.1 Add `CURRENT_FEATURE_SWITCH_FROM_ID=""` to the global state variable declarations in `ai/scripts/orchestrator.sh`

## 2. Startup prompt in fast path

- [ ] 2.1 In `_try_fast_path_feature_context`, after confirming the feature is valid and has a runnable step, add a guard: if `resume_mode == 1` or stdin is not a TTY, skip the prompt and proceed as before
- [ ] 2.2 When the prompt condition is met, display the two-option menu (`1. Proceed with current feature` / `2. Change feature`) to stderr and read the operator's choice in a validation loop
- [ ] 2.3 If the operator chooses option 1 (Proceed), continue with the current feature as before (no further change)
- [ ] 2.4 If the operator chooses option 2 (Change feature), set `CURRENT_FEATURE_SWITCH_FROM_ID="$SELECTED_FEATURE_ID"`, reset any reuse state variables populated by `try_reuse_feature_sync_for_resume` that would prevent re-discovery, and return 1

## 3. Feature picker CURRENT label

- [ ] 3.1 In `prompt_for_feature_selection_index`, before building the display list, check if `CURRENT_FEATURE_SWITCH_FROM_ID` is non-empty and find its index in the `feature_ids` array
- [ ] 3.2 If found, move the matching feature ID to index 0 of the display list and append ` (CURRENT)` to its displayed name
- [ ] 3.3 Ensure the returned index maps correctly back to the original candidate arrays in `ensure_feature_runtime_context` after the reorder

## 4. Test updates

- [ ] 4.1 Add a test in `tests/ai_scripts/orchestrator_assignment_tests.sh` for the interactive proceed case: valid current feature, operator enters 1 → reuses current feature without discovery
- [ ] 4.2 Add a test in `tests/ai_scripts/orchestrator_assignment_tests.sh` for the interactive change case: valid current feature, operator enters 2 → runs discovery, current feature appears first with `(CURRENT)` label
- [ ] 4.3 Add a test for non-interactive skip: valid current feature, stdin is not a TTY → auto-proceeds without prompt
- [ ] 4.4 Add a test that resume mode skips the startup prompt even when a valid current feature exists
- [ ] 4.5 Update any existing tests that assumed the fast path always proceeds silently when a valid current feature is found, to account for the new prompt

## 5. Documentation

- [ ] 5.1 Update `Readme.md` operator-facing documentation to describe the proceed-or-change startup prompt and its behavior in non-interactive mode
