## ADDED Requirements

### Requirement: Worker bootstrap configures local git ignore for feature_meta_sync.yaml
The worker init flow SHALL include `.asdlc_worker/feature_meta_sync.yaml` in the set of paths written to `.git/info/exclude` alongside other generated ASDLC runtime paths. This MUST be applied on both fresh install and update runs.

#### Scenario: feature_meta_sync.yaml exclude is applied during install
- **WHEN** the worker init script runs in install mode and calls the exclude-entry configuration step
- **THEN** `.git/info/exclude` in the target repository is updated to include `.asdlc_worker/feature_meta_sync.yaml`

#### Scenario: feature_meta_sync.yaml exclude is applied during update
- **WHEN** the worker init script runs in update mode and calls the exclude-entry configuration step
- **THEN** `.git/info/exclude` in the target repository is updated to include `.asdlc_worker/feature_meta_sync.yaml` if not already present

#### Scenario: Exclude entry does not duplicate on repeated runs
- **WHEN** the worker init script is run multiple times on the same target repository
- **THEN** `.asdlc_worker/feature_meta_sync.yaml` appears at most once in `.git/info/exclude`

### Requirement: Worker bootstrap does not create runtime mirror files
The worker init flow SHALL NOT create `.asdlc_worker/overmind/implementation_plan.md` or `.asdlc_worker/overmind/requirements_ears.md` as part of registration. In default mode, these files exist only at their bound-source locations under the bound ASDLC project repo.

#### Scenario: Init completes without writing runtime mirror plan
- **WHEN** the worker init script completes successfully in a fresh installation
- **THEN** `.asdlc_worker/overmind/implementation_plan.md` does not exist as a result of init

#### Scenario: Init completes without writing runtime mirror ears
- **WHEN** the worker init script completes successfully in a fresh installation
- **THEN** `.asdlc_worker/overmind/requirements_ears.md` does not exist as a result of init
