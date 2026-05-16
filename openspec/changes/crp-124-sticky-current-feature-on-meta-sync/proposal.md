## Why

Once crp-123 lands, the orchestrator's fast path reuses `feature_meta_sync.yaml` (the new 4-field metadata file) via `try_reuse_feature_meta_sync_for_resume`. Per crp-123's specs, that fast path can fail for two distinct reasons — (a) identity mismatch or missing bound-source paths (stale/invalid), or (b) reuse passes but the stored feature has no runnable step for this worker (valid-but-unrunnable). Both currently fall through to slow-path global discovery, which silently switches the worker to a different feature under the same bound project.

For a stale/invalid metadata file, that fall-through is correct: the operator has no current context to preserve. For a valid-but-unrunnable case, it is wrong: the operator was working on a real feature that is now blocked or exhausted, and the silent switch hides the real reason work cannot continue, breaks run-to-run determinism, and surprises operators who expected to keep working on the same feature.

This change supersedes crp-118 by re-stating the same sticky-feature intent on top of crp-123's new architecture. crp-118 will be closed once this change is filed.

## What Changes

- In `_try_fast_path_feature_context` (post-crp-123), when `try_reuse_feature_meta_sync_for_resume` returns 0 (reuse validation passed) but plan analysis for the worker shows no runnable step, the orchestrator MUST distinguish two sub-cases and fail fast:
  - **Blocked**: assigned step is gated by an incomplete upstream step → die with a message naming the current feature and the blocking step.
  - **Exhausted**: all assigned bullets are complete → die with a message naming the current feature as exhausted, and instructing the operator to remove `.asdlc_worker/feature_meta_sync.yaml` to allow reselection.
- Keep the existing fall-through to slow-path discovery when reuse validation itself fails (project_id/worker_uuid mismatch, missing bound-source plan, missing or empty bound-source ears, or `--resume <step>` not assigned to this worker). Those are stale-context cases where discovery is the correct next action.
- Apply the same sticky semantics on ordinary startup and on `--resume` invocations. `_try_fast_path_feature_context` is called from both routes, so the change covers both.
- Update the error messages to reference `.asdlc_worker/feature_meta_sync.yaml` (the new filename) rather than `feature_sync.yaml`.
- Do not introduce a new escape command. The error message naming `feature_meta_sync.yaml` as the file to clear is sufficient.

## Capabilities

### New Capabilities
- `sticky-current-feature-routing`: Orchestrator keeps a valid `feature_meta_sync.yaml`-pinned feature as the active run context and reports blocked or exhausted status explicitly instead of silently switching to another feature.

### Modified Capabilities
- `orchestrator-step-resume`: Resume reuse of a valid `feature_meta_sync.yaml` becomes authoritative; resume fails fast when the stored feature is blocked or exhausted instead of falling through to discovery.
- `orchestrator-worker-assigned-step-routing`: Non-resume startup routing also fails fast on blocked/exhausted current feature instead of silently switching.

## Impact

- Affected runtime script:
  - `ai/scripts/orchestrator.sh` (post-crp-123 code; specifically `_try_fast_path_feature_context` and the path where it returns 1 with `SELECTED_STEP` empty)
- Affected tests:
  - `tests/ai_scripts/orchestrator_assignment_tests.sh`
  - `tests/ai_scripts/orchestrator_resume_tests.sh`
- Affected docs/spec references:
  - `Readme.md`
  - selected-feature routing and reuse requirements in OpenSpec artifacts
- Dependency order:
  - **Must land after crp-123.** This change edits the renamed `try_reuse_feature_meta_sync_for_resume` and the 4-field `feature_meta_sync.yaml` schema introduced by crp-123.
- Supersedes:
  - **crp-118-stick-current-feature-on-reuse** — same intent, written against the pre-crp-123 schema. Close crp-118 when this change is filed.
