## 1. Orchestrator script changes

- [ ] 1.1 Remove the `printf "selection_mode: ..."` line from `write_feature_sync_metadata()` in `ai/scripts/orchestrator.sh`
- [ ] 1.2 Remove the `local selection_mode=""` variable declaration from `try_reuse_feature_sync_for_resume()` in `ai/scripts/orchestrator.sh`
- [ ] 1.3 Remove the `selection_mode="$(yaml_get_scalar ...)"` call from `try_reuse_feature_sync_for_resume()` in `ai/scripts/orchestrator.sh`
- [ ] 1.4 Remove the `if [[ -n "$selection_mode" ]]; then SELECTED_SELECTION_MODE="resume_reuse:$selection_mode"` block and keep the unconditional `SELECTED_SELECTION_MODE="resume_reuse"` assignment in `try_reuse_feature_sync_for_resume()`

## 2. Test updates

- [ ] 2.1 Update `tests/ai_scripts/orchestrator_resume_tests.sh` to remove any assertions that check for `selection_mode` in the written `feature_sync.yaml`
- [ ] 2.2 Update `tests/ai_scripts/orchestrator_resume_tests.sh` to add or update assertions that confirm `selection_mode` is absent from the written `feature_sync.yaml` after resume reuse
- [ ] 2.3 Update `tests/ai_scripts/orchestrator_assignment_tests.sh` to remove any assertions that check for `selection_mode` in the written `feature_sync.yaml`
- [ ] 2.4 Verify that `SELECTED_SELECTION_MODE` is still set to `resume_reuse` (not `resume_reuse:resume_reuse` or similar) in resume test assertions

## 3. Spec and doc cleanup

- [ ] 3.1 Remove or update any references to `selection_mode` in `Readme.md` that describe it as a field in `feature_sync.yaml`
- [ ] 3.2 Check other OpenSpec artifacts (main specs and docs) for `selection_mode` references and remove them if they describe it as a persisted field
