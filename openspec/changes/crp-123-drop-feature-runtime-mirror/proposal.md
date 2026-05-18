## Why

Orchestrator's default mode maintains two parallel copies of every feature's `implementation_plan.md` and `requirements_ears.md`: the source-of-truth under the bound ASDLC project repo (`<bound-project>/<feature-id>/`) and a runtime mirror under `.asdlc_worker/overmind/` on the worker's overmind branch. The orchestrator mirrors source → runtime on feature selection and runtime → source at end-of-step, with metadata in `.asdlc_worker/feature_sync.yaml` bridging the two. This drives ~200 lines of copy / clean-check / drift-validation logic in `ai/scripts/orchestrator.sh`, leaves stray runtime files on the overmind branch (requiring an explicit cleanup loop), and forces crp-117/crp-120 to patch around a schema that exists mostly to bridge the mirror.

Collapsing to a single source of truth — the bound ASDLC repo's per-feature files — removes the mirror entirely. AI agent writes during plan and ai_audit phases happen directly against the bound source's working tree (uncommitted), and a single end-of-step `git add + commit + pull --rebase + push` on the bound repo replaces the existing copy-back sync. Worker-local artifacts (step plans, designs, prompts, history, logs) stay on the overmind branch unchanged.

## What Changes

- Remove the runtime mirror of `implementation_plan.md` and `requirements_ears.md` from `.asdlc_worker/overmind/`. Default mode reads and writes those files directly at their bound-source paths under `<bound-project>/<feature-id>/`.
- Delete the mirror-related orchestrator functions: `mirror_selected_feature_to_runtime`, `copy_runtime_plan_worktree_to_file`, `restore_selected_source_plan_from_head`, `run_phase_with_optional_feature_sync`, the runtime-files-cleanup loop in `_try_fast_path_feature_context`, and the resume-mode runtime-files-missing guard. Shrink `commit_selected_source_plan_update_if_needed` and `run_global_plan_sync_attempt` (no tmp_runtime, no cmp, no copy-back step).
- Collapse `IMPLEMENTATION_PLAN_PRIMARY` / `RUNTIME_REQUIREMENTS_PATH` resolution so that in default mode they resolve to the bound-source paths; standalone mode keeps its local runtime paths (no bound project to write back to).
- Phase scripts (`ai_plan.sh`, `ai_design.sh`, `ai_implementation.sh`, `ai_user_review.sh`, `ai_audit.sh`) continue to consume `$ASDLC_RUNTIME_PLAN_PATH` / `$ASDLC_RUNTIME_EARS_PATH` unchanged; in default mode those env vars now resolve to the bound-source paths.
- **BREAKING**: Replace `.asdlc_worker/feature_sync.yaml` with a new file `.asdlc_worker/feature_meta_sync.yaml` containing only four fields: `project_id`, `worker_uuid`, `feature_id`, `selected_step`. Drop `source_*_path`, `runtime_*_path`, `source_feature_path`, `bound_project_path`, `overmind_source_path`, `selection_mode`, `runtime_branch`, and `requested_step`. Using a new filename guarantees any leftover reader of the old name fails loudly during migration rather than silently consuming stale schema.
- Adapt the pre-step bound-repo pull (existing `ensure_bound_project_synced_for_default_mode`) and the end-of-step commit + pull --rebase + push to operate on the bound repo's working-tree writes directly. Extend the existing pre-flight clean check to also detect uncommitted writes from a prior aborted run on the bound source plan/ears.
- Adjust `ai/scripts/post_review.sh` so it no longer needs `sync_implementation_plan_to_overmind_branch` for the runtime mirror in default mode; in standalone mode the existing behavior is preserved.
- Subsumes crp-117 (`selection_mode` removal) and the plan/ears portion of crp-120 (gitignore of runtime mirror) — those become moot because the fields and the runtime mirror no longer exist. The narrow remainder of crp-120 (ignore the metadata file in `.git/info/exclude`) is folded into this change for the new `feature_meta_sync.yaml` filename.

## Capabilities

### New Capabilities
- `bound-source-as-feature-runtime`: In default mode the orchestrator and phase scripts read and write `implementation_plan.md` and `requirements_ears.md` directly under the bound ASDLC project repo, with no per-worker runtime mirror.
- `feature-meta-sync-minimal-cache`: Worker runtime writes `.asdlc_worker/feature_meta_sync.yaml` (4 fields: `project_id`, `worker_uuid`, `feature_id`, `selected_step`) as a resume-time cache pointing at the bound-source feature directory.
- `feature-meta-sync-local-runtime-ignore`: Worker init configures `.git/info/exclude` so the new metadata file is invisible to git cleanliness checks.

### Modified Capabilities
- `orchestrator-worker-assigned-step-routing`: Routing selects a bound-source feature directory and writes `feature_meta_sync.yaml` (4 fields), without mirroring artifacts into `.asdlc_worker/overmind/`.
- `orchestrator-step-resume`: Resume reads `feature_meta_sync.yaml`, validates `project_id`/`worker_uuid` against the binding file, and locates plan/ears at `<bound-project>/<feature_id>/` via the binding-derived path rather than from cached source paths in the metadata file.
- `worker-overmind-registration`: Bootstrap registers `feature_meta_sync.yaml` (not `feature_sync.yaml`) for local-runtime ignore handling; the runtime mirror under `.asdlc_worker/overmind/implementation_plan.md` and `.asdlc_worker/overmind/requirements_ears.md` no longer exists in default mode.

## Impact

- Affected runtime scripts:
  - `ai/scripts/orchestrator.sh` (primary, ~200–250 line reduction)
  - `ai/scripts/post_review.sh` (`sync_implementation_plan_to_overmind_branch` becomes a no-op or removed in default mode; standalone behavior unchanged)
  - `ai/scripts/init_asdlc_worker.sh` (bootstrap ignore entry references `feature_meta_sync.yaml`)
- Affected helpers (path resolution unchanged; env var now resolves to bound source in default mode):
  - `ai/scripts/helpers/check_planning_readiness.sh`
  - `ai/scripts/helpers/check_ai_audit_disposition_readiness.sh`
- Affected tests (substantial shrinkage of feature-sync assertions, copy-back assertions, runtime-files cleanup assertions):
  - `tests/ai_scripts/orchestrator_assignment_tests.sh`
  - `tests/ai_scripts/orchestrator_resume_tests.sh`
  - `tests/ai_scripts/init_asdlc_worker_tests.sh`
  - Any `post_review` test exercising `sync_implementation_plan_to_overmind_branch`
- Affected docs / spec references:
  - `Readme.md`
  - OpenSpec artifacts that still describe `feature_sync.yaml` or the runtime mirror as part of the default-mode contract
- Relationship to in-flight changes:
  - crp-117 (`selection_mode` removal) — subsumed; can be archived without separate implementation.
  - crp-120 (gitignore `feature_sync.yaml` runtime state) — the runtime-mirror motivation evaporates; the narrow ignore-rule remainder is folded into this change for the new metadata filename.
- Migration (single coordinated cutover, no backwards-compatibility window):
  - The old file `.asdlc_worker/feature_sync.yaml` is never read; if present it is left in place untouched (operators may remove it). The new file `feature_meta_sync.yaml` is written on first run.
  - Existing runtime mirror files at `.asdlc_worker/overmind/implementation_plan.md` and `.asdlc_worker/overmind/requirements_ears.md` are no longer written. Orchestrator removes them on first default-mode run if untracked, to avoid confusion with the bound-source files.
