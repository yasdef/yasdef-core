## Purpose

Defines the only supported model pipeline configuration so invalid or partial worker setups fail clearly before a workflow run changes project state.

## ADDED Requirements

### Requirement: Complete model pipeline configuration
The worker SHALL accept a `models.md` configuration only when its non-comment rows define each model-driven phase exactly once: `design`, `planning`, `implementation`, `user_review`, `ai_audit`. Supported phase aliases MAY be normalized before comparing configured phase membership. Row order SHALL NOT control or invalidate the canonical workflow order.

#### Scenario: Complete configuration is accepted
- **WHEN** `models.md` contains one valid row for every model-driven phase
- **THEN** the worker accepts the model pipeline configuration

#### Scenario: Missing phase is rejected
- **WHEN** any required model-driven phase is absent from `models.md`
- **THEN** the worker rejects the configuration as incomplete

#### Scenario: Duplicate phase is rejected
- **WHEN** two or more rows normalize to the same model-driven phase
- **THEN** the worker rejects the configuration as having a duplicate phase

#### Scenario: Complete rows are written in a different order
- **WHEN** all required model-driven phases are present exactly once but their rows are not in canonical order
- **THEN** the worker accepts the configuration and executes the phases in canonical workflow order

### Requirement: Every active model row is valid
Each non-blank, non-comment `models.md` row SHALL contain a supported model-driven phase, a non-empty command, and a non-empty model using the documented pipe-delimited row format. A row MAY have one leading and one trailing outer pipe. The worker SHALL reject malformed rows instead of silently ignoring them and SHALL identify the invalid row or phase in its diagnostic.

#### Scenario: Row has too few required fields
- **WHEN** a non-comment row does not contain the phase, command, and model fields
- **THEN** the worker rejects the configuration and identifies the malformed row

#### Scenario: Required field is empty
- **WHEN** a model row has an empty phase, command, or model field
- **THEN** the worker rejects the configuration and identifies the invalid row or phase

#### Scenario: Markdown-style outer pipes are used
- **WHEN** a complete configuration writes rows as `| <phase> | <command> | <model> |` with one leading and trailing outer pipe
- **THEN** the worker parses the enclosed required fields and validates the configuration normally

#### Scenario: Unknown phase is configured
- **WHEN** a row names a phase that is not a supported model-driven phase
- **THEN** the worker rejects the configuration and identifies the unsupported phase

#### Scenario: Comments and blank lines are ignored
- **WHEN** a complete configuration also contains blank lines or lines whose first non-whitespace character is `#`
- **THEN** those lines do not affect configuration validation or phase order

### Requirement: Post-review remains worker-managed
The `post_review` phase SHALL NOT be configurable in `models.md`. After a complete model pipeline validates, the worker SHALL append `post_review` exactly once as the final workflow phase.

#### Scenario: Post-review is explicitly configured
- **WHEN** `models.md` contains a `post_review` row
- **THEN** the worker rejects the configuration as containing an unsupported configurable phase

#### Scenario: Valid pipeline is expanded
- **WHEN** a complete model pipeline configuration validates
- **THEN** the executed workflow order is `design`, `planning`, `implementation`, `user_review`, `ai_audit`, `post_review`

### Requirement: Model configuration is available at startup
The worker SHALL require `.asdlc_worker/setup/models.md` to exist as a readable file and SHALL report an actionable configuration error containing its path when it cannot be read.

#### Scenario: Models file is absent
- **WHEN** an operator starts a run and `.asdlc_worker/setup/models.md` does not exist
- **THEN** the run exits with an actionable error identifying the missing configuration path

#### Scenario: Models path is not a readable file
- **WHEN** an operator starts a run and the models path is a directory or cannot be read
- **THEN** the run exits with an actionable error identifying the unusable configuration path

### Requirement: Invalid configuration fails before workflow side effects
The worker SHALL validate the complete model pipeline at run startup, including resume runs, before the clean-mainline policy check, feature discovery or selection, bound-project synchronization, feature metadata writes, workflow branch creation, resume analysis, or model execution.

#### Scenario: Partial configuration fails at startup
- **WHEN** an operator starts a run with a partial `models.md` configuration
- **THEN** the run exits with an actionable configuration error
- **THEN** no feature is selected, no bound-project synchronization is attempted, no feature metadata or workflow branch is created, and no model command runs

#### Scenario: Invalid configuration is used for resume
- **WHEN** an operator starts a resume run with an invalid `models.md` configuration
- **THEN** the run exits at configuration validation before resume analysis or workflow side effects

### Requirement: Full runs start from a clean mainline
Every valid non-resume run SHALL require the worker repository to be on `main` or `master` with a clean working tree before feature discovery. Resume runs SHALL remain exempt from this startup policy so they can continue from an existing workflow branch.

#### Scenario: Non-resume run starts from a work branch
- **WHEN** an operator starts a valid non-resume run from a branch other than `main` or `master`
- **THEN** the run exits before feature discovery with the mainline requirement

#### Scenario: Non-resume run starts with local changes
- **WHEN** an operator starts a valid non-resume run from `main` or `master` with a dirty working tree
- **THEN** the run exits before feature discovery with the clean-working-tree requirement

#### Scenario: Resume run starts from a workflow branch
- **WHEN** an operator starts a valid resume run from an existing workflow branch
- **THEN** startup does not reject the run for being off `main` or `master`
