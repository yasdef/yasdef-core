## ADDED Requirements

### Requirement: Default-mode feature routing refreshes bound ASDLC project repo
The orchestrator process SHALL refresh the bound ASDLC project repo with `git -C <bound-asdlc-project-repo> pull --rebase` before default-mode worker-assigned feature routing reads any feature `implementation_plan.md`.

#### Scenario: Routing uses rebased ASDLC project checkout
- **WHEN** orchestrator runs in default mode and prepares worker-assigned feature routing
- **THEN** the orchestrator process SHALL run `git -C <bound-asdlc-project-repo> pull --rebase` before enumerating candidate feature folders
- **AND** worker assignment filtering SHALL read `implementation_plan.md` files from the rebased ASDLC project checkout

#### Scenario: Routing stops on ASDLC project rebase failure
- **WHEN** the bound ASDLC project repo cannot complete `git pull --rebase`
- **THEN** orchestrator SHALL exit non-zero before selecting a feature
- **AND** it SHALL not copy stale feature artifacts into worker runtime paths
