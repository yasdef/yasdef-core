## Context

Default-mode orchestrator treats the bound ASDLC project repo as the source of truth for feature `implementation_plan.md` and `requirements_ears.md`, but it currently reads and writes the local checkout directly. If another worker or coordinator updates the remote ASDLC repo, this worker can mirror stale artifacts or overwrite newer plan updates during sync-back.

The bound ASDLC project repo is already recorded in `.asdlc_worker/project_overmind.yaml` as `overmind_source_path`. Orchestrator uses that path for feature enumeration, mirroring, and selected source plan sync-back. This change keeps that boundary and adds Git synchronization around those existing operations.

Actor boundary: the worker operator still runs `.asdlc_worker/scripts/orchestrator.sh` from the worker repo. That orchestrator process is the only script actor that invokes ASDLC Git commands, and it invokes them with `git -C "$BOUND_PROJECT_PATH" ...` against the bound ASDLC project repo checkout. The user does not run separate ASDLC Git commands as part of the normal flow.

## Goals / Non-Goals

**Goals:**
- Pull-rebase the bound ASDLC project repo before reading feature plans for default-mode discovery and mirroring.
- Run a dedicated global implementation-plan sync handoff after `ai_audit` completes and before `post_review` starts.
- Copy the worker runtime `implementation_plan.md` into the selected ASDLC feature plan, commit it locally in the ASDLC repo, pull-rebase it onto the latest remote state, and push it.
- On outbound sync failure, explain what happened and offer the operator exactly two choices: retry sync or finish by skipping global sync and continuing to `post_review`.

**Non-Goals:**
- No changes to `--standalone`; it remains local-runtime-only.
- No new CLI flags.
- No remote sync for the worker repo itself.
- No three-way merge or custom conflict resolver for `implementation_plan.md`; Git rebase conflict handling is the conflict gate.
- No sync-back for `requirements_ears.md`; it remains a source input only.

## Decisions

1. Use `git pull --rebase` in the bound ASDLC project repo before inbound mirror and outbound sync-back.

   Rationale: the user asked specifically for pull-rebase, and this keeps local ASDLC history linear before the worker reads or writes feature artifacts. Alternative considered: `git fetch` plus `git reset --hard`; rejected because it is destructive and can discard local ASDLC changes.

2. Require the bound ASDLC path to be a Git worktree with a configured upstream in default mode.

   Rationale: default mode now promises remote freshness and push-back. If the path is not a Git repo or has no upstream, the script cannot satisfy that promise. `--standalone` remains the escape hatch when remote/source sync is not desired.

3. Run outbound sync only as an orchestrator handoff between `ai_audit` and `post_review`.

   Rationale: `ai_audit` is the phase that closes current-step `implementation_plan.md` bullets. `post_review` consolidates history/metrics and should not be responsible for mutating the global implementation plan. Running this handoff between those phases makes the global plan sync explicit and prevents later post-review logic from being the source of plan updates.

4. Copy, commit, rebase, then push for outbound sync.

   Rationale: the worker runtime plan is the step-completed output after `ai_audit`. Orchestrator copies that file to the selected ASDLC feature `implementation_plan.md`, stages and commits only that file in the ASDLC repo, then runs `git pull --rebase` so that local sync commit is replayed on top of any remote ASDLC changes. If Git detects conflicts, the handoff fails fast and the operator resolves the ASDLC repo state.

5. Push only after the ASDLC pull-rebase succeeds.

   Rationale: successful push means the global ASDLC implementation plan now contains this worker's completed-step plan update on top of remote changes. A failed push is reported as a sync failure and enters the two-option operator prompt.

6. Keep feature sync metadata as the traceability anchor and extend it only as needed.

   Rationale: `.asdlc_worker/feature_sync.yaml` already records selected feature and source/runtime paths. The outbound handoff should use that selected feature context instead of rediscovering a feature.

7. Orchestrator owns the timing of all ASDLC Git operations.

   Rationale: feature selection, runtime mirroring, phase execution, and sync-back already happen inside `orchestrator.sh`, so Git freshness checks must live in the same control flow. Inbound pull-rebase is invoked by orchestrator before `ensure_feature_runtime_context` scans feature folders and before `mirror_selected_feature_to_runtime` copies artifacts. Outbound copy, commit, pull-rebase, and push are invoked by orchestrator after the `ai_audit` phase completes and before the `post_review` phase begins.

8. Orchestrator announces the outbound global-plan sync handoff.

   Rationale: the operator should see that the implementation work for step `<N>` is finished, the local runtime implementation plan has been updated, and orchestrator is now syncing that update to the global ASDLC implementation plan before continuing to `post_review`.

9. Outbound sync failures use a two-option operator decision loop.

   Rationale: a failed global sync should not leave the operator guessing or force a full rerun. Orchestrator reports the failed action and context, then asks for exactly `1. retry` or `2. finish`. `retry` repeats the full outbound copy/commit/pull-rebase/push sequence for the same selected step. `finish` skips the global sync handoff for this run and continues to `post_review`, with the sync failure clearly reported.

## Risks / Trade-offs

- [Risk] `git pull --rebase` may fail due to conflicting remote ASDLC changes. -> Mitigation: report the failed action, repo path, selected feature plan, and step number; offer retry or finish.
- [Risk] Copying the worker runtime plan into the ASDLC repo before pull-rebase means the sync handoff must create a local commit before rebase. -> Mitigation: scope the commit to only the selected feature `implementation_plan.md` and use a deterministic sync commit message.
- [Risk] Push can fail if remote advances after local pull-rebase and commit. -> Mitigation: report the failed push and offer retry or finish; retry repeats copy, commit if needed, pull-rebase, and push.
- [Risk] Existing tests use plain temporary directories for ASDLC sources. -> Mitigation: update affected fixtures to initialize local Git repos with local bare remotes where default-mode remote sync is expected, and keep standalone tests unchanged.

## Migration Plan

1. Add orchestrator helpers for ASDLC repo Git validation, pull-rebase, scoped commit, and push.
2. Add the post-ai_audit/pre-post_review global implementation-plan sync handoff.
3. Replace phase-wrapper sync-back with explicit copy, scoped ASDLC commit, pull-rebase, and push in that handoff.
4. Update tests and docs.
5. Rollback is removing the new Git sync helper calls and returning to direct local copy behavior.

## Open Questions

- None.
