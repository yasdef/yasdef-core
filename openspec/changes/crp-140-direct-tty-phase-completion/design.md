## Context

When AI runner phases (codex, claude) run in direct-passthrough mode (no `stdout=PIPE`), the TUI renders natively in the terminal. The old close-marker mechanism — reading `PHASE_FINISHED_CAN_CLOSE` from the pipe — no longer works because there is no pipe. Currently the `uses_tty_wrapper` branch in `run_with_log` calls `proc.wait()` and the user must Ctrl-C manually after each phase.

The existing codebase uses git branch names as durable phase-state markers (`resume.py` checks `branch_exists("step-{step}-{feature_id}-implementation")` etc.). This same mechanism can carry the completion signal without any additional files or IPC channels.

## Goals / Non-Goals

**Goals:**
- Automatic AI process termination after a phase skill completes, in direct-tty mode
- Richer resume state: distinguish "phase started" from "phase completed cleanly"
- Zero new files in the worker repo; use git branch names as the only signal channel
- Backward-compatible: old branches (without `-DONE`) still detected by resume.py

**Non-Goals:**
- Timeout-based fallback: the existing "press Ctrl-C" message is the human fallback; no daemon timer needed
- Changing the signal mechanism for non-tty (pipe-based) runners — they keep the stream close-marker
- Detecting partial/crashed phase runs differently from "never started"

## Decisions

### Signal channel: git branch rename, not a file

**Decision:** The completion signal is a `git branch -m` rename from `step-{step}-{feat}-{phase}` to `step-{step}-{feat}-{phase}-DONE`, performed by a Python helper script called by the skill as its final act.

**Rationale:** Git branch names are already the state store for the resume system. Adding `-DONE` is additive to an existing pattern rather than introducing a new channel (file, socket, env var). The rename is atomic at the OS level, visible via `git branch`, and survives process death without cleanup.

**Alternatives considered:**
- *Signal file* (`.asdlc_worker/phase.signal`): works but adds an artifact that must be cleaned up and is invisible outside the process.
- *Log-file tailing*: reads raw `script` typescript bytes including ANSI codes; fragile, harder to test.
- *Named pipe (FIFO)*: requires setup/teardown, OS-specific edge cases.

### Poller lives in `process.py`, not in phase code

**Decision:** `_poll_for_done_branch(proc, git, step, feature_id, phase, interval=1.0)` is a private function in `process.py`. The `uses_tty_wrapper` branch in `run_with_log` calls it when the caller supplies branch-poll context (step, feature_id, phase).

**Rationale:** Phase code and runner definitions stay unchanged. The polling concern is an infrastructure detail of how a tty-wrapped process is managed, not a phase-level concern.

### Helper script called by skill, not by the model directly

**Decision:** The model calls `signal_phase_done.py` (installed by `init_asdlc_worker` into the worker's skill scripts directory). The script resolves the current branch name, validates it matches the expected pattern, and performs the rename.

**Rationale:** Keeps git operations out of the model's direct control. The script can validate preconditions (correct branch, clean state) and emit a clear error if called from an unexpected context.

### resume.py checks: additive OR

**Decision:** Every `git.branch_exists(f"step-{step}-{feat}-{phase}")` check in `resume.py` gains an `or git.branch_exists(f"step-{step}-{feat}-{phase}-DONE")`. No existing check is removed.

**Rationale:** Old worker repos that ran phases before this change have branches without `-DONE`; they must still be detected as complete. New runs produce `-DONE` branches and give resume.py the richer "completed cleanly" signal for future use.

## Risks / Trade-offs

- **Rename races:** if the AI process is killed between printing the "press Ctrl-C" message and the helper calling `git branch -m`, the rename never happens. The user sees the message and presses Ctrl-C — same as today. → No mitigation needed; the message is the fallback.
- **Branch name parsing in the helper:** the helper must reliably identify which phase branch it is on. If the branch name deviates from the `step-{step}-{feat}-{phase}` pattern, the helper should exit with a clear error rather than renaming something unexpected. → Validate with regex before rename.
- **poll_interval=1.0s latency:** yasdef terminates the AI process up to 1 second after the rename. Acceptable for interactive use. → No change needed.
- **`git branch -m` on a branch with upstream:** if the branch was pushed, the remote still has the old name. The rename is local-only. → Resume.py only checks local branches, so this is fine; the remote discrepancy is cosmetic.

## Open Questions

- Should `signal_phase_done.py` also push the `-DONE` branch to the remote so the orchestrator machine can detect completion remotely? (Out of scope for this change; note for future distributed-orchestration work.)
