## Context

`ensure_feature_runtime_context` uses a two-phase approach: a fast path (`_try_fast_path_feature_context`) that tries to reuse the stored `feature_sync.yaml`, followed by a slow-path full global candidate discovery that scans all features under the bound project. The fast path validates the stored feature context via `try_reuse_feature_sync_for_resume` and, if validation passes, also checks whether the feature has a runnable step. If either check fails, the fast path returns 1. When the fast path returns 1, the code unconditionally falls into global discovery.

The problem: "validation failed (stale/invalid feature)" and "validation passed but no runnable step" both return 1, so both outcomes fall through to global discovery. A feature that is valid but blocked or exhausted silently gets replaced by another feature from the project, hiding the real reason the current work cannot continue and breaking run-to-run determinism.

## Goals / Non-Goals

**Goals:**
- Make a successfully validated `feature_sync.yaml` sticky: once the stored feature passes reuse validation, the orchestrator commits to that feature and fails fast rather than discovering another one.
- Distinguish three outcomes from the fast path:
  1. Feature is stale or invalid → allow global discovery (existing behavior, no change).
  2. Feature is valid but blocked → fail fast with a blocker message.
  3. Feature is valid but exhausted (all assigned steps complete) → fail fast with a no-runnable-step message.
- Apply the same sticky semantics on both ordinary startup and `--resume` invocations.

**Non-Goals:**
- Changing how global discovery works when there is no `feature_sync.yaml` or when the stored feature is genuinely stale.
- Adding a new "clear current feature" command or user-facing escape hatch beyond mentioning it in the error message.
- Changing the `--standalone` mode path (unaffected).

## Decisions

### Distinguish valid-but-unrunnable inside `_try_fast_path_feature_context`

The fast path already separates "sync validation" (`try_reuse_feature_sync_for_resume` returns 0) from "step availability" (plan analysis). The fix is to stop returning 1 after sync validation succeeds and instead inspect the `_bb` and `_fa` variables from `analyze_feature_plan_for_worker` to emit the right fail-fast error.

Specifically:
- If `_fu` is empty and `_bb` is non-empty → the feature is blocked; call `die` with a blocker message.
- If `_fu` is empty and `_bb` is empty and `_fa` ≥ 1 → the feature is exhausted; call `die` with an exhaustion message.
- If `_fu` is empty and `_fa` is 0 → no assigned steps at all in the plan (should not happen for a valid feature sync, but treat as exhausted/unrunnable and die).

**Alternative considered:** Add a new return code from `try_reuse_feature_sync_for_resume` to signal "valid but unrunnable" vs "stale". Rejected: it would require callers to handle an extra code and makes the exit semantics harder to follow. Keeping the logic in `_try_fast_path_feature_context` is simpler.

### Error messages must guide the operator toward next action

The sticky error messages should name the feature and tell the operator how to escape: delete or clear `feature_sync.yaml` to trigger rediscovery. This ensures the behavior is transparent and not a dead end.

### Resume path uses the same fast path — no separate change needed

`_try_fast_path_feature_context` is called for both `resume_mode=0` and `resume_mode=1`. Making the fast path sticky covers both cases automatically.

## Risks / Trade-offs

- [Risk] Operators who relied on the silent fallback (e.g. to implicitly switch to a fresh feature after one is complete) will now see a fail-fast error. → Mitigation: the error message explains how to clear the stored context.
- [Risk] The `requested_step` path in `_try_fast_path_feature_context` skips plan re-analysis when `SELECTED_STEP` is already set by `try_reuse_feature_sync_for_resume`. If a requested step was valid during sync validation but is now blocked, it won't be caught by the new check. → Mitigation: `try_reuse_feature_sync_for_resume` already validates assigned-step membership; the requested-step path is correct to trust that result. The new check only runs when `SELECTED_STEP` is empty (no requested step), which is the ordinary auto-advance case.

## Migration Plan

1. In `_try_fast_path_feature_context`, after `try_reuse_feature_sync_for_resume` returns 0 and `SELECTED_STEP` is empty:
   a. Run `analyze_feature_plan_for_worker` and capture all four fields (`_fa`, `_ri`, `_fu`, `_bb`).
   b. If `_fu` is non-empty, set `SELECTED_STEP` and proceed as today.
   c. If `_fu` is empty and `_bb` is non-empty, call `die` with a blocked message referencing `$SELECTED_FEATURE_ID` and `$_bb`.
   d. If `_fu` is empty and `_bb` is empty, call `die` with an exhausted message referencing `$SELECTED_FEATURE_ID`.
2. Update `tests/ai_scripts/orchestrator_assignment_tests.sh` and `tests/ai_scripts/orchestrator_resume_tests.sh`:
   - Add tests for the blocked case (valid sync, blocked plan → fail with blocker message).
   - Add tests for the exhausted case (valid sync, all steps complete → fail with exhausted message).
   - Update or remove tests that expected silent fallthrough to global discovery when the fast path returned no runnable step.

Rollback: revert the `_try_fast_path_feature_context` change. Global discovery resumes for valid-but-unrunnable features.
