## 1. ASDLC Git Sync Helpers

- [x] 1.1 Add orchestrator helper to validate that the bound ASDLC project path is a Git worktree with a configured upstream in default mode.
- [x] 1.2 Add orchestrator helper to run `git pull --rebase` in the bound ASDLC project repo and fail fast with repo-specific guidance on error.
- [x] 1.3 Add orchestrator helper to stage, commit, and push only the selected feature source `implementation_plan.md` from the bound ASDLC project repo.

## 2. Inbound Mirror Flow

- [x] 2.1 Update `ai/scripts/orchestrator.sh` so the orchestrator process invokes `git -C "$BOUND_PROJECT_PATH" pull --rebase` before default-mode feature enumeration reads feature `implementation_plan.md` files.
- [x] 2.2 Ensure the orchestrator invokes the inbound pull-rebase before `mirror_selected_feature_to_runtime` copies the selected source `implementation_plan.md` and `requirements_ears.md` into `.asdlc_worker/overmind`.
- [x] 2.3 Keep `.asdlc_worker/feature_sync.yaml` focused on selected feature/source/runtime path traceability without adding mirror-time merge-base state.

## 3. Outbound Sync-Back Flow

- [x] 3.1 Replace phase-wrapper sync-back with a dedicated orchestrator handoff that runs after successful `ai_audit` for step `<N>` and before `post_review` starts.
- [x] 3.2 Print a handoff message stating that work for step `<N>` is finished, the implementation plan is updated, and orchestrator is trying to sync it with the global implementation plan.
- [x] 3.3 In that handoff, copy `.asdlc_worker/overmind/implementation_plan.md` to the selected ASDLC feature source `implementation_plan.md`.
- [x] 3.4 Stage only the selected ASDLC feature source `implementation_plan.md` and create a local ASDLC repo sync commit when the copy changes the source plan.
- [x] 3.5 Invoke `git -C "$BOUND_PROJECT_PATH" pull --rebase` after the local ASDLC sync commit so the copied plan update is replayed on top of remote ASDLC changes.
- [x] 3.6 Push the rebased ASDLC sync commit to the configured upstream when rebase succeeds.
- [x] 3.7 When copy, commit, pull-rebase, or push fails, print what happened and offer exactly two choices: `1. retry` and `2. finish`.
- [x] 3.8 Implement `1. retry` to rerun the full outbound sync sequence for the same selected step.
- [x] 3.9 Implement `2. finish` to skip global implementation-plan sync for that run and continue to `post_review` without reporting sync success.

## 4. Tests And Docs

- [x] 4.1 Add script tests for inbound pull-rebase before feature discovery using a local bare remote fixture.
- [x] 4.2 Add script tests proving outbound sync runs between `ai_audit` and `post_review`, prints the step sync message, copies the worker runtime plan to the ASDLC feature plan, commits, pull-rebases, and pushes.
- [x] 4.3 Add script tests for inbound rebase failure, outbound copy failure, outbound commit failure, outbound rebase conflict, and push failure messages.
- [x] 4.4 Add script tests for outbound failure prompt handling: retry repeats copy/commit/rebase/push, finish continues to `post_review`, and non-interactive failure exits before `post_review`.
- [x] 4.5 Update `Readme.md` to document default-mode ASDLC Git pull-rebase/push behavior, outbound retry/finish choices, and confirm `--standalone` bypasses it.
