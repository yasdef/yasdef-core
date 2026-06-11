## 1. Done-branch poller in process.py

- [ ] 1.1 Add `_poll_for_done_branch(proc, git, step, feature_id, phase, interval=1.0) -> bool` to `process.py`: polls `git.branch_exists(f"step-{step}-{feature_id}-{phase}-DONE")` every `interval` seconds; calls `_terminate_process(proc)` when found and returns `True`; returns `False` if process exits before branch appears
- [ ] 1.2 Extend `run_with_log` `uses_tty_wrapper` branch: accept `step`, `feature_id`, and `phase` kwargs (or a single `done_branch` kwarg); when provided, call `_poll_for_done_branch` instead of bare `proc.wait()`; use `_wait_after_marker_termination` after termination; set `effective_returncode = 0` when marker found
- [ ] 1.3 Add unit tests in `tests/unit/infra/test_process.py` covering: done-branch appears → process terminated + returncode 0; process exits before done-branch → actual returncode returned; SIGINT during polling → KeyboardInterrupt propagates

## 2. signal_phase_done helper script

- [ ] 2.1 Create `signal_phase_done.py` in the appropriate skill scripts source location: validate current branch matches `step-{step}-{feature_id}-{phase}` pattern; call `git branch -m <branch> <branch>-DONE`; exit 0 on success, non-zero with descriptive error on validation failure
- [ ] 2.2 Register `signal_phase_done.py` in `init_asdlc_worker` install manifest so it is copied into the worker repo alongside existing skill scripts
- [ ] 2.3 Add unit tests for `signal_phase_done.py`: valid branch renamed correctly; invalid branch name rejected with non-zero exit; git error propagated

## 3. resume.py done-branch detection

- [ ] 3.1 Update `ImplementationStateEvaluator.evaluate` in `resume.py`: add `or git.branch_exists(f"step-{step}-{feature.feature_id}-implementation-DONE")` to the existing implementation-complete check
- [ ] 3.2 Update `UserReviewStateEvaluator.evaluate` in `resume.py`: add `or git.branch_exists(f"step-{step}-{feature.feature_id}-user-review-DONE")` to the existing user-review-complete check
- [ ] 3.3 Add unit tests in `tests/unit/app/test_resume.py` covering: implementation-DONE branch → implementation complete; user-review-DONE branch → user_review complete; original branch (no -DONE) still recognised for backward compatibility

## 4. Skill integration

- [ ] 4.1 Add `signal_phase_done.py` call as the final step in each phase skill that runs in direct-tty mode (design, planning, implementation, user_review, ai_audit) — called after the skill prints the "press Ctrl-C" message
- [ ] 4.2 Verify end-to-end: run a phase in direct-tty mode, confirm process terminates automatically when done-branch appears and orchestrator advances to next phase
