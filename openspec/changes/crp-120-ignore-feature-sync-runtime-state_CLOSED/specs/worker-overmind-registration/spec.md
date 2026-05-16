## ADDED Requirements

### Requirement: Worker bootstrap configures local git ignore rules for feature-sync state
The worker init flow SHALL include `.asdlc_worker/feature_sync.yaml` in the set of paths written to `.git/info/exclude` alongside other generated ASDLC runtime paths. This MUST be applied on both fresh install and update runs.

#### Scenario: feature_sync.yaml exclude is applied during install
- **WHEN** the worker init script runs in install mode and calls the exclude-entry configuration step
- **THEN** `.git/info/exclude` in the target repository is updated to include `.asdlc_worker/feature_sync.yaml`

#### Scenario: feature_sync.yaml exclude is applied during update
- **WHEN** the worker init script runs in update mode and calls the exclude-entry configuration step
- **THEN** `.git/info/exclude` in the target repository is updated to include `.asdlc_worker/feature_sync.yaml` if not already present

#### Scenario: Exclude entry does not duplicate on repeated runs
- **WHEN** the worker init script is run multiple times on the same target repository
- **THEN** `.asdlc_worker/feature_sync.yaml` appears at most once in `.git/info/exclude`
