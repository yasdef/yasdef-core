## ADDED Requirements

### Requirement: Done-branch naming convention for phase completion
A phase branch renamed to `step-{step}-{feature_id}-{phase}-DONE` SHALL be treated as a durable, machine-readable signal that the named phase completed cleanly. The `-DONE` suffix is appended to the exact branch name that would have existed for the phase (e.g. `step-1.4-feat-plan-DONE` for the planning phase of step 1.4 of feature `feat`). Both the original branch name and the `-DONE` variant SHALL be recognised as equivalent "phase happened" signals in all resume and state-evaluation contexts.

#### Scenario: Done-branch is recognised as phase-complete signal
- **WHEN** a branch named `step-{step}-{feature_id}-{phase}-DONE` exists locally
- **THEN** all systems that check for phase completion treat this as equivalent to the original branch name existing

#### Scenario: Original branch still recognised for backward compatibility
- **WHEN** a branch named `step-{step}-{feature_id}-{phase}` exists (without `-DONE`) from a run before this change
- **THEN** all systems treat it as a valid "phase happened" signal, indistinguishable from the done-branch for completion detection purposes

#### Scenario: Done-branch provides richer resume signal
- **WHEN** only the original branch exists (without `-DONE`)
- **THEN** the phase is considered to have started but not necessarily completed cleanly
- **WHEN** the done-branch (`*-DONE`) exists
- **THEN** the phase is considered to have completed cleanly and the orchestrator may use this to prioritise the done-branch as the stronger completion evidence
