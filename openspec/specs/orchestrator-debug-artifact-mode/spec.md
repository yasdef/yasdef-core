# Capability: orchestrator-debug-artifact-mode

## Purpose
Define explicit debug-mode artifact behavior for orchestrator logs and prompts, with deterministic step-specific retention in debug mode and latest-only overwrite behavior in non-debug mode.

## Requirements

### Requirement: Explicit debug mode flag for artifact behavior
The orchestrator MUST provide an explicit `--debug` flag that controls log and prompt artifact naming/retention behavior, and debug mode MUST default to disabled when the flag is omitted.

#### Scenario: Debug mode defaults to false
- **WHEN** the operator runs the orchestrator without `--debug`
- **THEN** artifact behavior follows non-debug latest-only naming rules

#### Scenario: Debug mode enabled explicitly
- **WHEN** the operator runs the orchestrator with `--debug`
- **THEN** artifact behavior follows debug per-step/per-phase naming rules

### Requirement: Debug mode writes step-specific logs
When debug mode is enabled, orchestrator phase logs SHALL be written to `ai/logs` using deterministic step+phase specific names.

#### Scenario: Debug log naming
- **WHEN** debug mode is enabled and a phase executes for step `<step>`
- **THEN** the log file path uses `ai/logs/<project_name>-<phase>-<step>-log`

### Requirement: Non-debug mode writes latest-only logs
When debug mode is disabled, orchestrator phase logs SHALL be written to `ai/logs` using phase-level latest filenames, overwriting prior latest artifacts.

#### Scenario: Latest log overwrite behavior
- **WHEN** debug mode is disabled and the same phase is run multiple times
- **THEN** the orchestrator writes `ai/logs/<project_name>-<phase>-latest-log` and replaces the previous latest file contents for that phase

### Requirement: Debug mode keeps step-specific prompt artifact naming
When debug mode is enabled, orchestrator prompt artifacts SHALL use step-specific naming per phase.

#### Scenario: Debug prompt naming
- **WHEN** debug mode is enabled for phase `<phase>` and step `<step>`
- **THEN** prompt output path uses `ai/prompts/<phase>_prompts/<project_name>-<step>-<phase>-prompt.txt`

### Requirement: Non-debug mode uses latest-only prompt naming
When debug mode is disabled, orchestrator prompt artifacts SHALL be written to latest-only phase files.

#### Scenario: Latest prompt overwrite behavior
- **WHEN** debug mode is disabled for phase `<phase>`
- **THEN** prompt output path uses `ai/prompts/<phase>_prompts/<project_name>-latest-<phase>-prompt.txt` and is overwritten on subsequent runs

### Requirement: Non-debug mode preserves existing step-specific prompt files
When debug mode is disabled, existing step-specific prompt artifacts MUST remain unchanged.

#### Scenario: Legacy prompt artifacts are untouched
- **WHEN** step-specific prompt files already exist from previous debug runs
- **THEN** running the orchestrator with debug mode disabled does not modify those existing step-specific files

### Requirement: Artifact naming logic is centralized
The orchestrator implementation SHALL centralize log and prompt artifact naming rules so all phases apply the same normalization and mode-specific behavior.

#### Scenario: Consistent naming across phases
- **WHEN** design, planning, implementation, and review phases resolve artifact paths
- **THEN** each phase uses the same centralized naming helper contract for debug and non-debug modes

### Requirement: Canonical orchestrator log root directory
The orchestrator MUST treat `ai/logs` as the canonical root directory for orchestrator log artifacts in both debug and non-debug modes.

#### Scenario: Debug mode log path uses canonical root
- **WHEN** debug mode is enabled and a phase log path is resolved
- **THEN** the resolved path is under `ai/logs`

#### Scenario: Non-debug mode log path uses canonical root
- **WHEN** debug mode is disabled and a phase log path is resolved
- **THEN** the resolved path is under `ai/logs`

### Requirement: Legacy tmp log directory is not used for new writes
The orchestrator MUST NOT write new log artifacts to `ai/tmp/orchestrator_logs`.

#### Scenario: No new legacy-path log writes
- **WHEN** any orchestrator phase writes a log artifact
- **THEN** no write target is `ai/tmp/orchestrator_logs` or any child path under it

#### Scenario: Legacy directory is not required for successful runs
- **WHEN** `ai/tmp/orchestrator_logs` is absent and the orchestrator runs
- **THEN** execution succeeds with log artifacts written under `ai/logs`

### Requirement: Debug-mode validation tests use externalized test paths
Validation coverage for orchestrator debug artifact behavior MUST execute from test files located outside `ai/`.

#### Scenario: Debug artifact tests run from externalized directory
- **WHEN** debug artifact mode regression tests are invoked
- **THEN** the executed test file path is outside `ai/` and debug-mode behavior assertions remain unchanged
