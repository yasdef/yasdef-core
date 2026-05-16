## 1. Update Step Artifact Path Helpers in orchestrator.sh

- [ ] 1.1 Update `get_step_from_plan_path()` to extract only the numeric step from a feature-qualified filename (e.g., `step-2-auth-system.md` → `2`)
- [ ] 1.2 Update `try_get_step_from_plan_path()` regex to extract only the numeric step from a feature-qualified plan filename
- [ ] 1.3 Update `get_step_from_design_path()` regex to extract only the numeric step from `step-<N>-<feature>-design.md`
- [ ] 1.4 Update `get_latest_step_plan()` to require a feature-id argument and filter glob results to match `step-*-<feature-id>.md`

## 2. Update Artifact Path Construction in Phase Runner Functions

- [ ] 2.1 Update `run_implementation_phase()` in `orchestrator.sh` to use `step-$SELECTED_STEP-$SELECTED_FEATURE_ID.md` as the plan path (both in RESUME_STEP and normal paths)
- [ ] 2.2 Update `run_user_review_phase()` in `orchestrator.sh` to resolve the step plan via the feature-qualified path
- [ ] 2.3 Update `run_ai_audit_phase()` in `orchestrator.sh` to resolve the step plan and write the review result using feature-qualified paths
- [ ] 2.4 Update `run_design_phase()` in `orchestrator.sh` to write the design artifact to `step-$step-$SELECTED_FEATURE_ID-design.md`
- [ ] 2.5 Update the direct `review_artifact` path constructions in `orchestrator.sh` (lines ~1912, ~2177) to use `review_result-$step-$SELECTED_FEATURE_ID.md`

## 3. Update Resume Phase Completion Detection

- [ ] 3.1 Update `evaluate_design_phase()` to look for `step-$step-$SELECTED_FEATURE_ID-design.md`
- [ ] 3.2 Update `evaluate_implementation_phase()` to find the correct step plan at the feature-qualified path
- [ ] 3.3 Update `evaluate_user_review_phase()` and `is_user_review_complete_for_step()` to check the feature-qualified review result
- [ ] 3.4 Update `evaluate_ai_audit_phase()` to check `review_result-$step-$SELECTED_FEATURE_ID.md`

## 4. Add `--feature-id` Flag to Phase Scripts

- [ ] 4.1 Add `--feature-id` flag to `ai_plan.sh` and use `FEATURE_ID` when constructing the `OUT` path (`step-$STEP-$FEATURE_ID.md`)
- [ ] 4.2 Add `--feature-id` flag to `ai_implementation.sh` and use it when resolving the step plan path to read
- [ ] 4.3 Add `--feature-id` flag to `ai_user_review.sh` and use it when resolving the step plan path to read
- [ ] 4.4 Add `--feature-id` flag to `ai_audit.sh` and use it when constructing the review result output path and when resolving the source step plan path

## 5. Update Orchestrator Phase Invocations to Pass Feature ID

- [ ] 5.1 Update `run_planning_phase()` invocation of `ai_plan.sh` to pass `--feature-id "$SELECTED_FEATURE_ID"`
- [ ] 5.2 Update `run_implementation_phase()` invocation of `ai_implementation.sh` to pass `--feature-id "$SELECTED_FEATURE_ID"`
- [ ] 5.3 Update `run_user_review_phase()` invocation of `ai_user_review.sh` to pass `--feature-id "$SELECTED_FEATURE_ID"`
- [ ] 5.4 Update `run_ai_audit_phase()` invocation of `ai_audit.sh` to pass `--feature-id "$SELECTED_FEATURE_ID"`

## 6. Update Tests

- [ ] 6.1 Update `tests/ai_scripts/orchestrator_resume_tests.sh` to set up feature-qualified artifact files (`step-N-<feature>.md`, `step-N-<feature>-design.md`, `review_result-N-<feature>.md`) in feature-context test cases
- [ ] 6.2 Update `tests/ai_scripts/orchestrator_assignment_tests.sh` to assert feature-qualified artifact paths in feature-context step assignments
- [ ] 6.3 Run the orchestrator test suite and confirm all tests pass

## 7. Update Documentation

- [ ] 7.1 Update `Readme.md` step artifact path examples to show the feature-qualified format
