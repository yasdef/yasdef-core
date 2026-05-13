## ADDED Requirements

### Requirement: Bound ASDLC project repo is rebased before default-mode artifact reads
Before default-mode orchestrator reads feature `implementation_plan.md` files or mirrors a selected feature into worker runtime paths, the orchestrator process SHALL run `git -C <bound-asdlc-project-repo> pull --rebase` against the bound ASDLC project repo.

#### Scenario: Inbound rebase succeeds before feature discovery
- **WHEN** orchestrator starts default-mode feature discovery for a bound ASDLC project repo with a configured upstream
- **THEN** the orchestrator process SHALL run `git -C <bound-asdlc-project-repo> pull --rebase` before scanning feature folders
- **AND** feature discovery SHALL use the rebased local ASDLC checkout

#### Scenario: Inbound rebase fails
- **WHEN** `git pull --rebase` fails before feature discovery or artifact mirroring
- **THEN** orchestrator SHALL exit non-zero before copying feature artifacts into `.asdlc_worker/overmind`
- **AND** the error message SHALL identify the bound ASDLC project repo path
- **AND** the error message SHALL tell the operator to resolve the ASDLC repo rebase conflict or dirty state and rerun

#### Scenario: Standalone mode bypasses inbound rebase
- **WHEN** orchestrator runs with `--standalone`
- **THEN** it SHALL NOT run Git remote synchronization in the bound ASDLC project repo
- **AND** it SHALL continue to use existing local worker runtime files directly

### Requirement: Global plan sync runs between ai_audit and post_review
After `ai_audit` completes successfully for a step and before `post_review` starts, the orchestrator process SHALL run a global implementation-plan sync handoff for that step.

#### Scenario: ai_audit completes and post_review is next
- **WHEN** the `ai_audit` phase completes successfully for step `<N>`
- **AND** `post_review` is the next phase to run
- **THEN** orchestrator SHALL run global implementation-plan sync before invoking `post_review`
- **AND** the sync SHALL use the selected feature context already recorded for the run

#### Scenario: Sync announcement is shown
- **WHEN** orchestrator starts global implementation-plan sync for step `<N>`
- **THEN** it SHALL print a message stating that work for step `<N>` is finished
- **AND** the message SHALL state that the implementation plan is updated
- **AND** the message SHALL state that orchestrator is trying to sync it with the global implementation plan

### Requirement: Outbound sync copies worker runtime plan before ASDLC rebase
During global implementation-plan sync, orchestrator SHALL copy `.asdlc_worker/overmind/implementation_plan.md` into the selected ASDLC feature source `implementation_plan.md` before running `git pull --rebase` in the ASDLC project repo.

#### Scenario: Worker runtime plan is copied to selected ASDLC feature
- **WHEN** global implementation-plan sync starts for step `<N>`
- **THEN** orchestrator SHALL copy `.asdlc_worker/overmind/implementation_plan.md` to the selected feature source `implementation_plan.md`
- **AND** it SHALL stage only that selected feature source plan in the bound ASDLC project repo
- **AND** it SHALL create a local ASDLC repo commit for the selected feature plan update when the copy changes the source plan

#### Scenario: Commit fails
- **WHEN** orchestrator cannot create the local ASDLC repo sync commit after staging the selected feature source plan
- **THEN** orchestrator SHALL stop the sync attempt before pull-rebase or push
- **AND** it SHALL report what happened
- **AND** the message SHALL identify the selected feature source plan path
- **AND** the message SHALL offer exactly two operator choices: `1. retry` and `2. finish`

#### Scenario: Copy fails
- **WHEN** orchestrator cannot copy the worker runtime implementation plan into the selected ASDLC feature source plan
- **THEN** orchestrator SHALL stop the sync attempt before pull-rebase or push
- **AND** it SHALL report what happened
- **AND** the message SHALL identify the selected feature source plan path
- **AND** the message SHALL offer exactly two operator choices: `1. retry` and `2. finish`

### Requirement: Outbound sync rebases copied ASDLC plan update before push
After copying and locally committing the selected feature source `implementation_plan.md` update, orchestrator SHALL run `git -C <bound-asdlc-project-repo> pull --rebase` so the local ASDLC plan sync commit is replayed on top of remote ASDLC changes before push.

#### Scenario: Outbound rebase succeeds
- **WHEN** orchestrator has copied and committed a selected feature source plan update
- **THEN** it SHALL run `git -C <bound-asdlc-project-repo> pull --rebase`
- **AND** after rebase succeeds it SHALL push the local ASDLC repo branch to its configured upstream

#### Scenario: Outbound rebase conflicts
- **WHEN** `git pull --rebase` fails during global implementation-plan sync
- **THEN** orchestrator SHALL stop the sync attempt before push
- **AND** it SHALL report what happened
- **AND** the message SHALL identify the bound ASDLC project repo path
- **AND** the message SHALL identify the selected feature source plan path
- **AND** the message SHALL offer exactly two operator choices: `1. retry` and `2. finish`

#### Scenario: Push fails after rebase
- **WHEN** outbound pull-rebase succeeds but push fails
- **THEN** orchestrator SHALL report what happened with a message identifying the bound ASDLC project repo path
- **AND** the message SHALL tell the operator that the ASDLC plan sync commit exists locally but could not be pushed
- **AND** the message SHALL offer exactly two operator choices: `1. retry` and `2. finish`

#### Scenario: Copy produces no source plan change
- **WHEN** copying the worker runtime plan into the selected ASDLC feature source plan produces no Git change
- **THEN** orchestrator SHALL skip the local ASDLC sync commit
- **AND** it SHALL still run `git -C <bound-asdlc-project-repo> pull --rebase` before deciding whether push is needed
- **AND** it SHALL skip push when no local ASDLC commit is pending after rebase

### Requirement: Outbound sync failure prompt controls retry or post_review continuation
When copy, commit, outbound pull-rebase, or push fails during global implementation-plan sync, orchestrator SHALL explain the failed action and ask the operator to choose either retry or finish.

#### Scenario: Operator chooses retry
- **WHEN** outbound global implementation-plan sync fails
- **AND** the operator chooses `1. retry`
- **THEN** orchestrator SHALL retry the full outbound sync sequence for the same selected step
- **AND** the retry sequence SHALL copy the worker runtime plan, stage and commit the selected ASDLC feature plan when changed, run `git pull --rebase`, and push when needed

#### Scenario: Operator chooses finish
- **WHEN** outbound global implementation-plan sync fails
- **AND** the operator chooses `2. finish`
- **THEN** orchestrator SHALL skip the global implementation-plan sync for that run
- **AND** it SHALL continue to `post_review`
- **AND** it SHALL not report the global implementation-plan sync as successful

#### Scenario: Non-interactive outbound sync failure
- **WHEN** outbound global implementation-plan sync fails in a non-interactive shell
- **THEN** orchestrator SHALL exit non-zero before `post_review`
- **AND** the error message SHALL include the same two choices so the operator knows how to rerun interactively
