## Why

When `needs_tty=True` runners (codex, claude) run in direct-passthrough mode (crp-140 predecessor work), the subprocess output flows straight to the real terminal and the TUI renders natively. The trade-off is that the close-marker (`PHASE_FINISHED_CAN_CLOSE`) can no longer be detected by reading the pipe — there is no pipe. Without detection, the AI process stays alive after the phase skill finishes and the user must press Ctrl-C manually to advance the orchestrator.

## What Changes

- Add `_tail_for_marker(proc, log_path, marker) -> bool` to `process.py`: polls `log_path` (written by `script`) for the close-marker string using a seek-based incremental read at ~50 ms intervals; terminates the process group via SIGTERM when found; returns `True` if marker was found before natural exit.
- In `run_with_log`, replace the bare `proc.wait()` in the `uses_tty_wrapper` branch with: call `_tail_for_marker` when `close_marker` is set, then use `_wait_after_marker_termination` (existing timeout-to-SIGKILL escalation) so the subprocess is reliably reaped.
- Set `effective_returncode = 0` when marker was found (consistent with the pipe-based path).
- Add unit tests covering: marker found before process exit, process exits before marker, SIGINT during tail.

## Capabilities

### New Capabilities
- `direct-tty-phase-completion`: automatic phase advancement when running AI tools in direct-tty (native terminal) mode — the orchestrator detects phase completion via log file tailing and terminates the AI process, matching the behaviour of the old pipe-based close-marker path without breaking the native TUI.

### Modified Capabilities
- `run_with_log` direct-tty path: was `proc.wait()` (manual Ctrl-C required); becomes marker-aware with automatic termination.

## Impact

- `src/yasdef_worker/infra/process.py`: add `_tail_for_marker`; extend the `uses_tty_wrapper` branch in `run_with_log`.
- `tests/unit/infra/test_process.py`: new tests for the tail-based marker path.
- No change to runner definitions, phase code, or caller sites.
