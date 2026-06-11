## ADDED Requirements

### Requirement: Phase completion detection via done-branch polling in direct-tty mode
When `run_with_log` runs a subprocess in direct-tty mode (no stdout pipe), it SHALL poll for a `-DONE` git branch suffix every 1 second. When the done-branch is detected, it SHALL terminate the subprocess process group via SIGTERM and treat the run as successful (effective returncode 0), consistent with the existing pipe close-marker path.

#### Scenario: Done-branch detected terminates the AI process
- **WHEN** a phase runs in direct-tty mode and the done-branch (e.g. `step-1.4-feat-plan-DONE`) appears in the local git repository
- **THEN** `run_with_log` sends SIGTERM to the subprocess process group within 1 second of detection
- **THEN** `run_with_log` waits for the process to exit (with existing SIGKILL escalation on timeout) and returns effective returncode 0

#### Scenario: Process exits before done-branch appears
- **WHEN** a phase process exits naturally before the done-branch is created (e.g. skill crash)
- **THEN** `run_with_log` returns the process's actual exit code without sending any signal
- **THEN** the caller receives the non-zero returncode and the error path applies normally

#### Scenario: SIGINT during polling terminates the AI process
- **WHEN** the user presses Ctrl-C while the poller is waiting for the done-branch
- **THEN** the SIGINT relay sends SIGINT to the subprocess process group
- **THEN** KeyboardInterrupt propagates to the caller, same as the non-tty path

### Requirement: signal_phase_done helper renames the branch atomically
A Python helper script `signal_phase_done.py` SHALL be installed into the worker repo by `init_asdlc_worker`. When called by a skill as its final act, it SHALL rename the current git branch from `step-{step}-{feature_id}-{phase}` to `step-{step}-{feature_id}-{phase}-DONE` using `git branch -m`. It SHALL validate that the current branch matches the expected pattern before renaming and exit with a non-zero code and a human-readable error if validation fails.

#### Scenario: Helper renames branch on valid phase branch
- **WHEN** `signal_phase_done.py` is called from a branch matching `step-{step}-{feature_id}-{phase}`
- **THEN** the branch is renamed to `step-{step}-{feature_id}-{phase}-DONE`
- **THEN** the script exits 0

#### Scenario: Helper rejects unexpected branch name
- **WHEN** `signal_phase_done.py` is called from a branch that does not match the `step-*-*-{phase}` pattern
- **THEN** the script exits non-zero and prints a descriptive error without performing any rename

#### Scenario: Human fallback when helper is not called
- **WHEN** a skill finishes and the helper is not called (e.g. skill crash before the final step)
- **THEN** no done-branch is created, `run_with_log` continues polling, and the user sees the "press Ctrl-C" message emitted earlier by the skill
- **THEN** pressing Ctrl-C terminates the AI process via the existing SIGINT relay
