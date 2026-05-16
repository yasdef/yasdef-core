## 1. Update Branch Name Construction in Phase Scripts

- [ ] 1.1 Add `--feature-id` flag to `ai_implementation.sh` and use it in `ensure_implementation_branch()` to construct `step-$STEP-$FEATURE_ID-implementation` when non-empty
- [ ] 1.2 Add `--feature-id` flag to `ai_user_review.sh` and use it in `ensure_user_review_branch()` to qualify `implementation_branch` and `target` names
- [ ] 1.3 Add `--feature-id` flag to `ai_audit.sh` and use it in `ensure_review_branch()` to qualify `implementation_branch`, `user_review_branch`, and `target` names
- [ ] 1.4 Update `ai_plan.sh` invocation in `run_planning_phase()` in `orchestrator.sh` to pass `--branch-name step-$SELECTED_STEP-$SELECTED_FEATURE_ID-plan` when `SELECTED_FEATURE_ID` is non-empty

## 2. Update Orchestrator Phase Invocations

- [ ] 2.1 Update `run_implementation_phase()` in `orchestrator.sh` to pass `--feature-id "$SELECTED_FEATURE_ID"` to `ai_implementation.sh` when `SELECTED_FEATURE_ID` is non-empty
- [ ] 2.2 Update `run_user_review_phase()` in `orchestrator.sh` to pass `--feature-id "$SELECTED_FEATURE_ID"` to `ai_user_review.sh` when `SELECTED_FEATURE_ID` is non-empty
- [ ] 2.3 Update `run_ai_audit_phase()` in `orchestrator.sh` to pass `--feature-id "$SELECTED_FEATURE_ID"` to `ai_audit.sh` when `SELECTED_FEATURE_ID` is non-empty

## 3. Update Branch Detection and Resume Logic

- [ ] 3.1 Update `implementation_branch_exists_for_step()` in `orchestrator.sh` to construct `step-$step-$SELECTED_FEATURE_ID-implementation` when `SELECTED_FEATURE_ID` is non-empty
- [ ] 3.2 Update `user_review_branch_exists_for_step()` in `orchestrator.sh` to construct `step-$step-$SELECTED_FEATURE_ID-user-review` when `SELECTED_FEATURE_ID` is non-empty
- [ ] 3.3 Update the fast-path plan branch check in `orchestrator.sh` (line ~196) to use the feature-qualified plan branch name when `SELECTED_FEATURE_ID` is non-empty
- [ ] 3.4 Update the context-file skip check (line ~195) to match against `step-$SELECTED_STEP-$SELECTED_FEATURE_ID-*` when `SELECTED_FEATURE_ID` is non-empty

## 4. Update Step Extraction from Branch Names

- [ ] 4.1 Update `get_step_from_branch_name()` in `orchestrator.sh` to first try matching `^step-([0-9]+([.][0-9]+)*)-[^-].*-(plan|implementation|user-review|review|ai-audit)$` (numeric step, feature-qualified) and fall back to the existing pattern
- [ ] 4.2 Apply the same two-pass regex update to `get_step_from_branch_name()` in `ai_user_review.sh`
- [ ] 4.3 Apply the same two-pass regex update to `get_step_from_branch_name()` in `ai_audit.sh`

## 5. Update Tests

- [ ] 5.1 Update `tests/ai_scripts/orchestrator_resume_tests.sh` to set up feature-qualified branch names (`step-N-<feature>-implementation`, `step-N-<feature>-user-review`) in feature-context test cases
- [ ] 5.2 Update `tests/ai_scripts/orchestrator_assignment_tests.sh` to assert feature-qualified branch names in feature-context step assignments
- [ ] 5.3 Run the orchestrator test suite and confirm all tests pass

## 6. Update Documentation

- [ ] 6.1 Update `Readme.md` branch-naming examples to show the feature-qualified format alongside the standalone format
