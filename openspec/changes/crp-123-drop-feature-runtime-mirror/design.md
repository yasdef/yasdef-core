## Context

Today the orchestrator (`ai/scripts/orchestrator.sh`) maintains a per-worker runtime mirror of each feature's `implementation_plan.md` and `requirements_ears.md` under `.asdlc_worker/overmind/`, copied from the bound ASDLC project repo at `<bound-project>/<feature-id>/`. The mirror is created by `mirror_selected_feature_to_runtime` on feature selection and synced back to the source at end-of-step via `run_global_plan_sync_attempt` (`orchestrator.sh:2095-2159`). A metadata file at `.asdlc_worker/feature_sync.yaml` carries both source and runtime paths, plus identity fields, to bridge the two copies across invocations.

Three forces push us to collapse the mirror:

1. **Drift surface**: every read/write needs to choose between source and runtime path, and helpers (`copy_runtime_plan_worktree_to_file`, `ensure_selected_source_plan_clean_before_sync`, `restore_selected_source_plan_from_head`) exist to detect and repair drift.
2. **Branch dirtiness**: the runtime copies live as untracked files on the overmind branch; `_try_fast_path_feature_context` has an explicit cleanup loop (`orchestrator.sh:1375-1387`) to delete them before step branches fork. This is what crp-120 was trying to patch.
3. **Schema as bridge, not state**: `feature_sync.yaml` is mostly two copies of path information that could be re-derived from the binding file plus the feature id. crp-117 already tried to strip one field; the larger collapse is the simpler answer.

Writes to `implementation_plan.md` happen at two distinct moments per step, not just one:
- During **plan phase**, the AI marks the `Plan and discuss the step` bullet `[x]`. Enforced at `ai/scripts/helpers/check_planning_readiness.sh:118-164`.
- During **ai_audit phase**, the AI marks the remaining current-step bullets `[x]`. Required by `ai/scripts/ai_audit.sh:567-569` and gated by `check_ai_audit_disposition_readiness.sh`.

`ai/scripts/ai_implementation.sh:604` explicitly forbids writes to `implementation_plan.md` from the implementation phase; `ai_design.sh` and `ai_user_review.sh` only read it. Therefore the bound source receives writes at exactly the plan and ai_audit phases; everything else is read-only.

`ai/scripts/post_review.sh` currently runs `sync_implementation_plan_to_overmind_branch` to move the updated plan file from the review branch back to the overmind branch (`post_review.sh:650-696`). That step exists solely to keep the runtime mirror current and disappears with the mirror.

Standalone mode (`--standalone`) has no bound project and continues to use local `.asdlc_worker/overmind/implementation_plan.md` and `requirements_ears.md`. It is not in scope here except where shared code paths fork.

## Goals / Non-Goals

**Goals:**
- Remove the runtime mirror of plan/ears in default mode; bound-source files are the only copy.
- Replace `feature_sync.yaml` with `feature_meta_sync.yaml` containing only `project_id`, `worker_uuid`, `feature_id`, `selected_step`.
- Keep phase scripts unchanged at their interface (`$ASDLC_RUNTIME_PLAN_PATH` / `$ASDLC_RUNTIME_EARS_PATH`); only the resolution of those env vars changes in default mode.
- Single end-of-step sync remains: `git add + commit + pull --rebase + push` on the bound repo. No intermediate per-phase commits.
- Preserve the existing pre-flight clean check on the bound source plan/ears so a prior aborted run with uncommitted writes is detected, not silently included in the next step's commit.
- Preserve standalone-mode behavior unchanged.
- Subsume crp-117 and the runtime-mirror portion of crp-120 within this change.

**Non-Goals:**
- Changing standalone-mode runtime layout or contracts.
- Changing AI agent prompts or phase-script logic for what gets marked `[x]` and when. The agent still ticks `Plan and discuss the step` during plan phase and remaining bullets during ai_audit — those writes simply land on the bound source rather than a runtime mirror.
- Cross-machine concurrency between multiple workers on the same feature. Each worker has its own bound-repo clone; merge-time conflicts on `implementation_plan.md` are already mediated by the existing pull --rebase + push retry/finish prompt (`orchestrator.sh:2178-2202`). No new locking is introduced.
- Renaming or redesigning the binding file, the overmind branch contract, or per-step artifact paths under `.asdlc_worker/`.
- Backwards-compatibility with the old `feature_sync.yaml` schema. The new filename guarantees a hard cutover.

## Decisions

### 1. Bound source as the only copy of plan/ears in default mode

In default mode, `IMPLEMENTATION_PLAN_PRIMARY` and `RUNTIME_REQUIREMENTS_PATH` resolve to `<BOUND_PROJECT_PATH>/<feature_id>/implementation_plan.md` and `.../requirements_ears.md`. The `$ASDLC_RUNTIME_PLAN_PATH` / `$ASDLC_RUNTIME_EARS_PATH` env vars exported to phase scripts hold the same paths. Phase scripts and helpers consume those env vars unchanged.

In standalone mode the env vars continue to resolve to local `.asdlc_worker/overmind/...` paths exactly as today. The fork happens once during orchestrator setup and is invisible to phase scripts and helpers.

**Alternative considered:** keep a runtime mirror but make it a hardlink/symlink to the bound source. Rejected because cross-filesystem cases break, and the mirror's value was always conceptual transactionality — which we keep via the single end-of-step commit, not via two physical copies.

### 2. Two write points, one commit

Plan phase and ai_audit phase both write directly to the bound-source `implementation_plan.md`, both leaving the bound repo's working tree dirty. The orchestrator does NOT commit between phases. At end-of-step (before `post_review`), `run_global_plan_sync_before_post_review` runs `git add <feature-id>/implementation_plan.md + git commit + pull --rebase + push` on the bound repo. This preserves the current transactional unit ("one commit per step's plan changes") and keeps the existing retry/finish failure prompt.

**Alternative considered:** commit after each write (two commits per step). Rejected — adds two git operations per step for no reliability gain, and pollutes ASDLC history with mid-step commits.

**Alternative considered:** stash between phases. Rejected — adds complexity and obscures debugging.

### 3. Pre-flight clean check covers aborted runs

`ensure_selected_source_plan_clean_before_sync` already exists (`orchestrator.sh:1983-2000`) and is called inside `run_global_plan_sync_attempt`. We extend the pre-step check (in `ensure_bound_project_synced_for_default_mode`) so that on entry — before the AI is allowed to write — the bound feature's plan and ears must either be clean OR contain only changes the operator explicitly acknowledges. If dirty, orchestrator dies with a clear error directing the operator to `git restore` / commit / stash in the bound repo. This catches the "aborted run left uncommitted plan edits" case.

**Alternative considered:** auto-discard via `git restore --source=HEAD`. Rejected — destructive default that could erase legitimate operator edits.

### 4. New filename: `feature_meta_sync.yaml`

The hard rename forces every reader of the old name to fail loudly during code review and CI. Any spec, doc, or test still referencing `feature_sync.yaml` is a bug we want to see, not paper over.

Schema:

```yaml
project_id: '<from binding>'
worker_uuid: '<from binding>'
feature_id: '<selected feature dir basename>'
selected_step: '<step number string>'
```

Fields dropped and why each is safe to drop:
- `source_implementation_plan_path` / `source_requirements_ears_path` — derivable from `BOUND_FEATURES_ROOT/$feature_id/{implementation_plan.md,requirements_ears.md}`.
- `runtime_implementation_plan_path` / `runtime_requirements_ears_path` — no runtime copy exists.
- `source_feature_path` — derivable.
- `bound_project_path` / `overmind_source_path` — already in the binding file; loaded via `load_project_binding`.
- `selection_mode` — already proposed for removal in crp-117; not consumed by any routing decision.
- `runtime_branch` — `RUNTIME_BRANCH="overmind"` is hardcoded at `orchestrator.sh:19`; persisting it is dead validation.
- `requested_step` — transient input from the CLI; not load-bearing across invocations.

**Alternative considered:** drop the metadata file entirely (rediscover every invocation). Rejected per operator preference for a small persisted pointer.

### 5. Resume reuse simplification

`try_reuse_feature_sync_for_resume` shrinks dramatically. New behavior:

1. If `feature_meta_sync.yaml` is absent → return failure; fall through to discovery.
2. Read `project_id`, `worker_uuid`, `feature_id`, `selected_step`.
3. Validate `project_id` and `worker_uuid` equal the binding file's values. If not → return failure.
4. Compute `source_plan = BOUND_FEATURES_ROOT/$feature_id/implementation_plan.md` and `source_ears = .../requirements_ears.md`. Validate both exist and ears is non-empty.
5. If a `--resume <step>` is passed, validate the plan still has that step assigned to this worker via `plan_has_assigned_step_for_worker`. If not → return failure (fall to discovery, which will either re-prompt or fail with a clearer error).
6. Set `SELECTED_FEATURE_ID`, `SELECTED_FEATURE_PATH`, `IMPLEMENTATION_PLAN_FILE` to the source paths. No mirror copy. No untracked-runtime cleanup loop.

`write_feature_meta_sync_metadata` writes exactly the 4 fields on every successful selection or resume reuse.

### 6. post_review changes

`sync_implementation_plan_to_overmind_branch` (`post_review.sh:650-696`) is no longer needed in default mode — the plan never lived on the overmind branch in the first place. Two options:

- **Option A:** delete the function and its call site.
- **Option B (chosen):** gate the function on `STANDALONE_MODE` so standalone keeps its current behavior of syncing the local plan from review-branch back to overmind. This keeps standalone tests stable and minimizes surface area touched in post_review.

In default mode, post_review continues to commit the review artifact and update history normally; it just does not touch `implementation_plan.md` at all (the orchestrator's global plan sync has already committed and pushed the plan to the bound repo by the time post_review runs — sequencing preserved by `orchestrator.sh:3055-3056`).

### 7. Migration on first upgraded run

- An existing `.asdlc_worker/feature_sync.yaml` is never read; left untouched. Operators may remove it. No automatic deletion (avoids surprising the operator with a "where did my file go" question).
- Existing runtime mirror files at `.asdlc_worker/overmind/implementation_plan.md` and `.asdlc_worker/overmind/requirements_ears.md`, if present as untracked files on the overmind branch from a prior run, are removed on first default-mode invocation. This uses the existing pattern from `_try_fast_path_feature_context` for cleaning untracked runtime files; the cleanup is kept narrowly scoped to those two filenames during the first upgraded run only — no permanent cleanup loop.
- `.git/info/exclude` gains a `.asdlc_worker/feature_meta_sync.yaml` entry on init/upgrade. The old `.asdlc_worker/feature_sync.yaml` exclude entry (if added by a prior crp-120 attempt) is left in place; it is harmless when the file is no longer written.

## Risks / Trade-offs

- **Risk:** Aborted run leaves uncommitted edits in the bound repo working tree → Mitigation: pre-flight clean check at step start dies with a clear error; operator decides whether to commit/restore. Same failure surface as today's `ensure_selected_source_plan_clean_before_sync`, just enforced earlier.
- **Risk:** Two workers on the same bound-repo clone race → Mitigation: not in scope; each worker is expected to have its own clone. The existing `pull --rebase` + retry/finish loop handles cross-clone merge cases at push time exactly as today.
- **Risk:** Phase scripts have unexpected reads of `.asdlc_worker/overmind/implementation_plan.md` literal path (not via env var) → Mitigation: a grep of `ai/scripts/` shows ~30 such literal references, all in printf templates and error messages that include the path as informational text rather than reading from it. Audit those references during implementation; replace literals with the env var or with a default-mode-aware path message.
- **Risk:** Tests assert against literal `feature_sync.yaml` paths or runtime-mirror locations → Mitigation: planned test rewrite in tasks; CI catches anything missed.
- **Trade-off:** Operators lose the ability to inspect a "current runtime view" of the plan separate from the bound source. Acceptable — the bound source IS the runtime view; there is nothing to compare it to.
- **Trade-off:** Standalone mode and default mode diverge slightly in env-var resolution. Acceptable — the fork is localized to one setup function and is invisible to phase scripts.

## Migration Plan

1. Land orchestrator + helper + post_review code changes behind one PR.
2. CI runs the existing test suites; failures point at residual `feature_sync.yaml` / runtime-mirror references — fix in the same PR.
3. Update docs and Readme.
4. Archive crp-117 and crp-120 alongside this change (their scope is subsumed); leave a one-line note in each pointing here.
5. **Rollback:** revert the PR. Existing operator installs with a residual `.asdlc_worker/feature_sync.yaml` are unaffected by the revert; new metadata file at `.asdlc_worker/feature_meta_sync.yaml` is harmless leftover after rollback.

## Open Questions

- **Q1:** Should `run_global_plan_sync_attempt`'s retry/finish prompt also apply when the bound repo is in a state where `pull --rebase` fails with a merge conflict on `implementation_plan.md` itself? Current behavior prompts retry/finish; the new model does not change that surface — confirm during implementation that no new failure mode is introduced.
- **Q2:** Does resume need to validate that `feature_meta_sync.yaml`'s `selected_step` still exists in the (potentially externally updated) bound source plan, or fall back silently to slow-path discovery? Preference is silent fallback (matches today's behavior on missing source paths); document the choice in the spec scenario.
- **Q3:** First-upgrade cleanup of the two runtime-mirror files — should this be feature-flagged or unconditional? Preference is unconditional one-time cleanup driven by the upgraded code path itself (no flag) since the files are always untracked and the upgraded code never writes them again.
