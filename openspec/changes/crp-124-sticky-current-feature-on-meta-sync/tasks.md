## 1. Orchestrator script changes

- [ ] 1.1 In `_try_fast_path_feature_context` in `ai/scripts/orchestrator.sh` (post-crp-123), after `try_reuse_feature_meta_sync_for_resume` returns 0 and `SELECTED_STEP` is empty, capture all four fields from `analyze_feature_plan_for_worker` into `_fa`, `_ri`, `_fu`, `_bb`
- [ ] 1.2 If `_fu` is non-empty, set `SELECTED_STEP="$_fu"` and proceed as today
- [ ] 1.3 If `_fu` is empty and `_bb` is non-empty, call `die` with a message naming `$SELECTED_FEATURE_ID` and the blocking step `$_bb`; do not return 1
- [ ] 1.4 If `_fu` is empty and `_bb` is empty (and the feature passed reuse validation), call `die` with a message naming `$SELECTED_FEATURE_ID` as exhausted and instructing the operator to remove `.asdlc_worker/feature_meta_sync.yaml` to allow reselection; do not return 1
- [ ] 1.5 Confirm requested-step path (when `SELECTED_STEP` is already set by `try_reuse_feature_meta_sync_for_resume`) is unchanged and continues to skip the post-success plan-analysis branch

## 2. Test updates — assignment tests

- [ ] 2.1 Add a test in `tests/ai_scripts/orchestrator_assignment_tests.sh` for the blocked case: valid `.asdlc_worker/feature_meta_sync.yaml`, assigned step blocked by upstream → orchestrator exits non-zero with a blocker message and does not run slow-path discovery
- [ ] 2.2 Add a test in `tests/ai_scripts/orchestrator_assignment_tests.sh` for the exhausted case: valid `.asdlc_worker/feature_meta_sync.yaml`, all assigned steps checked → orchestrator exits non-zero with an exhausted message and does not run slow-path discovery
- [ ] 2.3 Assert the exhausted-case error message names `.asdlc_worker/feature_meta_sync.yaml` as the file to remove
- [ ] 2.4 Update or remove any existing tests that expected silent fall-through to slow-path discovery when the fast path found no runnable step for a valid `feature_meta_sync.yaml`

## 3. Test updates — resume tests

- [ ] 3.1 Add a test in `tests/ai_scripts/orchestrator_resume_tests.sh` for the blocked resume case: valid `.asdlc_worker/feature_meta_sync.yaml`, blocked step, `--resume` (with no step arg) → exits non-zero with blocker message
- [ ] 3.2 Add a test in `tests/ai_scripts/orchestrator_resume_tests.sh` for the exhausted resume case: valid `.asdlc_worker/feature_meta_sync.yaml`, all steps done, `--resume` → exits non-zero with exhausted message
- [ ] 3.3 Confirm existing tests that exercise the fall-through-on-identity-mismatch case still pass (these test stale-context discovery, which is unchanged)

## 4. Documentation

- [ ] 4.1 Update `Readme.md` if it describes feature selection or reuse behavior to reflect that a valid stored feature is now sticky and fails fast instead of silently rediscovering
- [ ] 4.2 Mention the escape path: remove `.asdlc_worker/feature_meta_sync.yaml` to reselect

