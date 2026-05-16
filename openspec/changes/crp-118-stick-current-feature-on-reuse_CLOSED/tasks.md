## 1. Orchestrator script changes

- [ ] 1.1 In `_try_fast_path_feature_context` in `ai/scripts/orchestrator.sh`, after `try_reuse_feature_sync_for_resume` returns 0 and `SELECTED_STEP` is empty, capture all four fields from `analyze_feature_plan_for_worker` (assign `_fa`, `_ri`, `_fu`, `_bb`)
- [ ] 1.2 If `_fu` is empty and `_bb` is non-empty, call `die` with a message naming `$SELECTED_FEATURE_ID` and the blocking step `$_bb` instead of returning 1
- [ ] 1.3 If `_fu` is empty and `_bb` is empty, call `die` with a message naming `$SELECTED_FEATURE_ID` as exhausted (all assigned steps complete) and instructing the operator to clear `feature_sync.yaml` to reselect, instead of returning 1

## 2. Test updates

- [ ] 2.1 Add a test in `tests/ai_scripts/orchestrator_assignment_tests.sh` for the blocked case: valid `feature_sync.yaml`, assigned step blocked by upstream → orchestrator exits non-zero with a blocker message and does not run discovery
- [ ] 2.2 Add a test in `tests/ai_scripts/orchestrator_assignment_tests.sh` for the exhausted case: valid `feature_sync.yaml`, all assigned steps checked → orchestrator exits non-zero with an exhausted message and does not run discovery
- [ ] 2.3 Add a test in `tests/ai_scripts/orchestrator_resume_tests.sh` for the blocked resume case: valid `feature_sync.yaml`, blocked step, `--resume` → exits non-zero with blocker message
- [ ] 2.4 Add a test in `tests/ai_scripts/orchestrator_resume_tests.sh` for the exhausted resume case: valid `feature_sync.yaml`, all steps done, `--resume` → exits non-zero with exhausted message
- [ ] 2.5 Update or remove any existing tests that expected silent fallthrough to global discovery when the fast path found no runnable step for a valid feature sync

## 3. Documentation

- [ ] 3.1 Update `Readme.md` if it documents feature selection or reuse behavior to reflect that a valid stored feature is now sticky and fails fast instead of silently rediscovering
