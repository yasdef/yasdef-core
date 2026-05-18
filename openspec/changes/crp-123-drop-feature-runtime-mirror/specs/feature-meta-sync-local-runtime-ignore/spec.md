## ADDED Requirements

### Requirement: Worker init adds feature_meta_sync.yaml to local git excludes
The ASDLC worker init flow SHALL add `.asdlc_worker/feature_meta_sync.yaml` to the target repository's `.git/info/exclude` file so that the orchestrator's selected-feature runtime state file is never treated as untracked branch content.

#### Scenario: Fresh install adds exclude entry
- **WHEN** the worker init script runs a fresh installation in a valid target repository
- **THEN** `.git/info/exclude` in the target repository contains the line `.asdlc_worker/feature_meta_sync.yaml`

#### Scenario: Update run adds exclude entry idempotently
- **WHEN** the worker init script runs in update mode on an existing installation
- **THEN** `.git/info/exclude` contains `.asdlc_worker/feature_meta_sync.yaml` exactly once regardless of how many times init has been run

#### Scenario: feature_meta_sync.yaml not tracked after init
- **WHEN** the orchestrator writes `.asdlc_worker/feature_meta_sync.yaml` after a successful worker init
- **THEN** git does not report the file as untracked or dirty in the target repository worktree

### Requirement: feature_meta_sync.yaml is not a durable committed path
`.asdlc_worker/feature_meta_sync.yaml` SHALL NOT be included in the set of paths that worker init commits to the target repository. It is local runtime state and MUST NOT appear in git history or on any branch.

#### Scenario: Init does not commit feature_meta_sync.yaml
- **WHEN** the worker init script completes successfully
- **THEN** `.asdlc_worker/feature_meta_sync.yaml` is not staged or committed by the init flow
