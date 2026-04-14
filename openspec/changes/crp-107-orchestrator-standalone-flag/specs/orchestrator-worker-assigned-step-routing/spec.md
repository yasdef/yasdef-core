## MODIFIED Requirements

### Requirement: Next-step discovery runs from synced coordinator branch
The orchestrator SHALL support two routing discovery modes. Without `--standalone`, it SHALL switch to local Git branch `overmind`, sync it from remote Git branch `overmind`, and continue ASDLC-backed artifact routing. With `--standalone`, it SHALL bypass synced-branch ASDLC artifact discovery and route directly from local `overmind/implementation_plan.md`.

#### Scenario: Local overmind branch missing in default mode
- **WHEN** orchestrator starts next-step discovery without `--standalone` and local Git branch `overmind` does not exist
- **THEN** orchestrator exits non-zero with an explicit fail-fast error
- **AND** it does not continue discovery

#### Scenario: Remote overmind branch missing in default mode
- **WHEN** orchestrator runs without `--standalone` and remote Git branch `overmind` is missing during sync
- **THEN** orchestrator exits non-zero with an explicit fail-fast error
- **AND** it does not parse `implementation_plan.md`

#### Scenario: Remote sync failure in default mode
- **WHEN** orchestrator runs without `--standalone` and cannot complete sync of local `overmind` from remote `overmind`
- **THEN** orchestrator exits non-zero with an explicit fail-fast error
- **AND** it does not start design or implementation

#### Scenario: Standalone mode bypasses synced-branch artifact discovery
- **WHEN** orchestrator starts next-step discovery with `--standalone`
- **THEN** it does not perform ASDLC artifact discovery and mirroring as part of routing setup
- **AND** it routes assigned-step work from local `overmind/implementation_plan.md`
