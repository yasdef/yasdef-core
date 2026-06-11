## Why

When `needs_tty=True` runners (codex, claude) run in direct-passthrough mode, the AI process output flows straight to the real terminal and the TUI renders natively. The close-marker (`PHASE_FINISHED_CAN_CLOSE`) can no longer be detected by reading a pipe — there is no pipe. Without detection, the AI process stays alive after the skill finishes and the user must press Ctrl-C manually to advance the orchestrator.

## What Changes

- Add a Python helper script `signal_phase_done.py` (installed into the worker repo alongside existing skill scripts). The skill calls this helper as its final act. The helper renames the current git branch from `step-{step}-{feature_id}-{phase}` to `step-{step}-{feature_id}-{phase}-DONE` via `git branch -m`.
- Add `_poll_for_done_branch(proc, git, step, feature_id, phase, interval=1.0)` to `process.py`: checks for the `-DONE` branch every second; terminates the process group via SIGTERM when found; returns `True` if the done-branch was detected before natural process exit.
- In `run_with_log`, replace the bare `proc.wait()` in the `uses_tty_wrapper` branch with a call to `_poll_for_done_branch` when `close_marker` context is available, then use `_wait_after_marker_termination` for reliable reaping.
- Update `resume.py` phase evaluators to check for both the original branch name and the `-DONE` variant (additive, backward-compatible). This gives resume.py a richer signal: branch exists → phase started; branch-DONE exists → phase completed cleanly.
- The existing "press Ctrl-C so yasdef can start the next phase" message remains the human fallback when the helper is not called (e.g. skill crash mid-phase). No timeout needed — the message is the fallback.

## Capabilities

### New Capabilities
- `direct-tty-phase-completion`: automatic phase advancement in direct-tty mode — the skill calls `signal_phase_done.py`, which renames the current branch to `*-DONE`; yasdef polls branch names every second and terminates the AI process when the done-branch appears, matching the old pipe close-marker behaviour without breaking native TUI rendering.
- `phase-done-branch-signal`: the `-DONE` branch suffix becomes a durable, git-visible completion marker that resume.py can use to distinguish "phase started" from "phase completed cleanly", providing richer state than the current branch-exists-only checks.

### Modified Capabilities
- `run_with_log` direct-tty path: was bare `proc.wait()` (manual Ctrl-C required); becomes done-branch-aware with automatic SIGTERM on detection.
- `resume.py` phase evaluators: each `branch_exists(step-...-phase)` check gains an OR for `branch_exists(step-...-phase-DONE)`, backward-compatible with old branches.

## Impact

- `src/yasdef_worker/infra/process.py`: add `_poll_for_done_branch`; extend the `uses_tty_wrapper` branch in `run_with_log`.
- `src/yasdef_worker/app/resume.py`: additive `-DONE` checks in `ImplementationStateEvaluator` and `UserReviewStateEvaluator`.
- New helper script `signal_phase_done.py` installed by `init_asdlc_worker` alongside existing skill scripts.
- `tests/unit/infra/test_process.py`: new tests for the done-branch polling path.
- `tests/unit/app/test_resume.py`: new tests covering `-DONE` branch detection.
- No change to phase code or orchestrator caller sites.
