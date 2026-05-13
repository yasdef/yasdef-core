## Why

Worker orchestration currently reads and writes ASDLC feature artifacts from the local bound project checkout without first synchronizing that checkout with its remote. This can copy stale `implementation_plan.md` into the worker runtime, and later overwrite coordinator-side updates when syncing worker plan changes back.

## What Changes

- Before default-mode feature discovery and runtime mirroring, orchestrator will run a pull-rebase sync in the bound ASDLC project repo so copied feature artifacts come from the latest remote state.
- After `ai_audit` completes and before `post_review` starts, orchestrator will announce that step `<N>` is finished and that it is syncing the updated worker runtime `implementation_plan.md` with the global ASDLC implementation plan.
- During that handoff, orchestrator will copy the worker runtime `implementation_plan.md` into the selected ASDLC feature `implementation_plan.md`, commit that selected plan update in the ASDLC repo, run `git pull --rebase` so the local plan update is replayed on top of remote changes, and then push.
- If copy, commit, pull-rebase, or push cannot complete cleanly, orchestrator will explain what happened and offer exactly two choices: `1. retry` to rerun the outbound sync sequence, or `2. finish` to skip global sync for this run and continue to `post_review`.
- `--standalone` remains unchanged and continues to bypass ASDLC artifact discovery and remote sync.

## Capabilities

### New Capabilities
- `asdlc-project-git-rebase-sync`: Git-safe synchronization of bound ASDLC project repositories before worker artifact mirror and during the post-ai_audit worker plan sync handoff.

### Modified Capabilities
- `orchestrator-worker-assigned-step-routing`: Default-mode feature discovery must synchronize the bound ASDLC project repo before reading feature `implementation_plan.md` files.
- `overmind-process-artifact-ownership`: Source-of-truth ASDLC feature artifacts remain authoritative, but worker plan updates must be copied, committed, rebased, and pushed through the ASDLC project repo before post_review.

## Impact

- Affected scripts: `.asdlc_worker/scripts/orchestrator.sh` source template in `ai/scripts/orchestrator.sh`.
- Affected tests: `tests/ai_scripts/orchestrator_assignment_tests.sh` or a focused new script test under `tests/ai_scripts/`.
- Affected docs: `Readme.md` orchestration and artifact-sync sections.
- External system: bound ASDLC project repo must be a Git worktree with a reachable configured upstream for default-mode remote sync and push.
