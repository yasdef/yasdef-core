## 1. Orchestrator default-mode path resolution

- [ ] 1.1 Add a setup function in `ai/scripts/orchestrator.sh` that, in default mode, resolves `IMPLEMENTATION_PLAN_PRIMARY` and `RUNTIME_REQUIREMENTS_PATH` to `<BOUND_PROJECT_PATH>/<feature_id>/implementation_plan.md` and `.../requirements_ears.md` after `load_project_binding` and feature selection
- [ ] 1.2 Ensure the same setup function leaves standalone-mode resolution (local `.asdlc_worker/overmind/...`) unchanged
- [ ] 1.3 Audit `ai/scripts/orchestrator.sh` for hard-coded references to `.asdlc_worker/overmind/implementation_plan.md` or `.../requirements_ears.md` outside the standalone-mode block and remove or route them through the resolver from 1.1

## 2. feature_meta_sync.yaml writer and reader

- [ ] 2.1 Introduce `FEATURE_META_SYNC_FILE` variable in `ai/scripts/orchestrator.sh` pointing at `$ASDLC_WORKER_HOME/feature_meta_sync.yaml`
- [ ] 2.2 Add `write_feature_meta_sync_metadata()` that writes exactly `project_id`, `worker_uuid`, `feature_id`, `selected_step` (no other fields)
- [ ] 2.3 Replace all call sites of the old `write_feature_sync_metadata()` with `write_feature_meta_sync_metadata()`
- [ ] 2.4 Rewrite `try_reuse_feature_sync_for_resume()` (rename to `try_reuse_feature_meta_sync_for_resume()`) to: (a) read only 4 fields from `feature_meta_sync.yaml`, (b) validate `project_id`/`worker_uuid` against the binding, (c) derive plan/ears paths from `BOUND_PROJECT_PATH`/`feature_id`, (d) validate derived plan exists and ears is non-empty, (e) validate `plan_has_assigned_step_for_worker` when `--resume <step>` is passed
- [ ] 2.5 Ensure `feature_sync.yaml` is never read by orchestrator.sh after this change

## 3. Remove runtime mirror code

- [ ] 3.1 Delete `mirror_selected_feature_to_runtime()` in `ai/scripts/orchestrator.sh`
- [ ] 3.2 Delete `copy_runtime_plan_worktree_to_file()` in `ai/scripts/orchestrator.sh`
- [ ] 3.3 Delete `restore_selected_source_plan_from_head()` in `ai/scripts/orchestrator.sh`
- [ ] 3.4 Delete the wrapper `run_phase_with_optional_feature_sync()` and update its caller at `orchestrator.sh:3058` to invoke `run_phase` directly
- [ ] 3.5 Remove the untracked-runtime-files cleanup loop in `_try_fast_path_feature_context()` (current `orchestrator.sh:1375-1387`)
- [ ] 3.6 Remove the resume-mode runtime-files-missing guard in `_try_fast_path_feature_context()` (current `orchestrator.sh:1389-1393`)
- [ ] 3.7 Remove the `mirror_selected_feature_to_runtime` call inside `ensure_feature_runtime_context` slow path (current `orchestrator.sh:1533`) and replace with `IMPLEMENTATION_PLAN_FILE` assignment to the bound-source plan

## 4. Slim end-of-step sync

- [ ] 4.1 Rewrite `run_global_plan_sync_attempt()` in `ai/scripts/orchestrator.sh` to: stage the bound-source plan with `git add`, commit if anything is staged, run `pull --rebase`, push if a commit was created — with no `cp`/`cmp`/`tmp_runtime` step
- [ ] 4.2 Shrink `commit_selected_source_plan_update_if_needed()` accordingly (no `restore_selected_source_plan_from_head` callback, no copy step)
- [ ] 4.3 Preserve the existing retry/finish operator prompt at `prompt_for_outbound_sync_failure_action()` and its caller `run_global_plan_sync_before_post_review()`

## 5. Pre-step clean check on bound source

- [ ] 5.1 Add a pre-step clean check inside `ensure_bound_project_synced_for_default_mode()` (or its caller) that verifies `<BOUND_PROJECT_PATH>/<feature_id>/implementation_plan.md` has no uncommitted changes before plan/ai_audit phases run
- [ ] 5.2 On dirty state, exit non-zero with a message identifying the dirty file, the bound repo path, and remediation options (`commit`, `stash`, `git restore`)
- [ ] 5.3 Confirm the existing in-sync clean check `ensure_selected_source_plan_clean_before_sync()` continues to work or fold its responsibility into the pre-step check

## 6. post_review.sh changes

- [ ] 6.1 Gate `sync_implementation_plan_to_overmind_branch()` in `ai/scripts/post_review.sh` so it executes only in standalone mode (or is no-op'd in default mode); preserve standalone behavior
- [ ] 6.2 Remove or guard the `IMPLEMENTATION_PLAN_REL_PATH=".asdlc_worker/overmind/implementation_plan.md"` constant for default mode if no longer referenced
- [ ] 6.3 Audit `post_review.sh` for any other implicit dependencies on the runtime mirror existing on the `overmind` branch in default mode

## 7. init_asdlc_worker.sh changes

- [ ] 7.1 Update `ai/scripts/init_asdlc_worker.sh` to add `.asdlc_worker/feature_meta_sync.yaml` to `.git/info/exclude` (instead of, or in addition to, any existing `feature_sync.yaml` entry)
- [ ] 7.2 Ensure the exclude entry is idempotent across repeated init runs
- [ ] 7.3 Verify init does not create `.asdlc_worker/overmind/implementation_plan.md` or `.asdlc_worker/overmind/requirements_ears.md`

## 8. One-time migration cleanup

- [ ] 8.1 On first default-mode orchestrator run, if `.asdlc_worker/overmind/implementation_plan.md` exists as untracked content on the overmind branch, remove it
- [ ] 8.2 Same for `.asdlc_worker/overmind/requirements_ears.md`
- [ ] 8.3 Do not auto-delete `.asdlc_worker/feature_sync.yaml`; leave it for the operator

## 9. Tests — orchestrator_assignment_tests.sh

- [ ] 9.1 Update `tests/ai_scripts/orchestrator_assignment_tests.sh` to assert that no copy of `implementation_plan.md` or `requirements_ears.md` is created under `.asdlc_worker/overmind/` after feature selection in default mode
- [ ] 9.2 Update assertions on the persisted metadata file: expect `.asdlc_worker/feature_meta_sync.yaml` with exactly 4 fields (`project_id`, `worker_uuid`, `feature_id`, `selected_step`)
- [ ] 9.3 Remove any assertions on `selection_mode`, `source_*_path`, `runtime_*_path`, `runtime_branch`, `requested_step`, `bound_project_path`, `overmind_source_path`, `source_feature_path` keys
- [ ] 9.4 Update phase-script env-var assertions: `$ASDLC_RUNTIME_PLAN_PATH` and `$ASDLC_RUNTIME_EARS_PATH` resolve to bound-source paths in default mode

## 10. Tests — orchestrator_resume_tests.sh

- [ ] 10.1 Update `tests/ai_scripts/orchestrator_resume_tests.sh` to test resume reuse from `feature_meta_sync.yaml` with 4-field schema
- [ ] 10.2 Add a test that resume falls through to discovery when `feature_meta_sync.yaml` has mismatched `project_id`
- [ ] 10.3 Add a test that resume falls through when derived `<BOUND_PROJECT_PATH>/<feature_id>/implementation_plan.md` is missing
- [ ] 10.4 Add a test that an existing `.asdlc_worker/feature_sync.yaml` (legacy) is ignored and does not affect resume
- [ ] 10.5 Add a test that resume on a non-overmind branch in default mode does not require local runtime mirror files
- [ ] 10.6 Remove any test cases that assert on the runtime-files cleanup loop or on `selection_mode` accumulation

## 11. Tests — init_asdlc_worker_tests.sh

- [ ] 11.1 Update `tests/ai_scripts/init_asdlc_worker_tests.sh` to assert `.git/info/exclude` contains `.asdlc_worker/feature_meta_sync.yaml`
- [ ] 11.2 Assert init does not create `.asdlc_worker/overmind/implementation_plan.md` or `.asdlc_worker/overmind/requirements_ears.md`
- [ ] 11.3 Assert idempotency of the new exclude entry

## 12. Tests — post_review (any existing coverage)

- [ ] 12.1 Identify any post_review tests that assert `sync_implementation_plan_to_overmind_branch` runs in default mode and update them to expect that path is skipped in default mode and exercised only under `--standalone`
- [ ] 12.2 Add a default-mode test that the bound-source `implementation_plan.md` is committed and pushed by the end-of-step sync, and that no commit lands on the overmind branch for that file

## 13. Pre-step clean-check tests

- [ ] 13.1 Add a test in `tests/ai_scripts/orchestrator_assignment_tests.sh` (or a new file) that the orchestrator exits non-zero when the bound-source plan has uncommitted changes at step start
- [ ] 13.2 Assert the error message identifies the dirty file and the bound repo path

## 14. Documentation

- [ ] 14.1 Update `Readme.md` to describe the single-source-of-truth feature plan/ears model, remove references to the runtime mirror, and document the 4-field `feature_meta_sync.yaml`
- [ ] 14.2 Audit `openspec/specs/**` for any committed specs that describe `feature_sync.yaml`, the runtime mirror, or `selection_mode` as part of the contract; flag in this change for archive-time delta sync
- [ ] 14.3 Update any operator-facing docs that describe the contents of `.asdlc_worker/overmind/` in default mode

## 15. Archive related in-flight changes

- [ ] 15.1 After this change is implemented and archived, archive `crp-117-remove-feature-sync-selection-mode` with a one-line note pointing to this change
- [ ] 15.2 Archive `crp-120-ignore-feature-sync-runtime-state` with a one-line note pointing to this change

## 16. Final verification

- [ ] 16.1 Grep the repo for any remaining references to `feature_sync.yaml`, `mirror_selected_feature_to_runtime`, `copy_runtime_plan_worktree_to_file`, `restore_selected_source_plan_from_head`, `run_phase_with_optional_feature_sync`, `selection_mode`, `runtime_implementation_plan_path`, `runtime_requirements_ears_path` — none should remain except in archived changes
- [ ] 16.2 Run the full test suite under `tests/ai_scripts/` and confirm green
- [ ] 16.3 Run `openspec validate crp-123-drop-feature-runtime-mirror --strict` and confirm it passes
