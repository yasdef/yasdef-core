## ADDED Requirements

### Requirement: Orchestrator always routes under a bound feature context
The orchestrator SHALL only route assigned steps when a feature has been selected through the ASDLC binding flow. The orchestrator SHALL NOT expose any operator-controlled flag, environment variable, or runtime fallback that bypasses ASDLC feature discovery and reads local `overmind/` runtime files directly.

#### Scenario: Default mode is the only mode
- **WHEN** orchestrator starts
- **THEN** it follows the ASDLC-bound discovery flow (worker UUID resolution, candidate feature scan, feature selection, runtime sync)
- **AND** it does not accept `--standalone` or any equivalent bypass flag

#### Scenario: Selected feature identity is always non-empty after selection
- **WHEN** orchestrator completes feature selection successfully
- **THEN** the selected feature identity is a non-empty value
- **AND** downstream phase invocations can rely on that identity being present without conditional checks

#### Scenario: Unreachable ASDLC binding fails fast with no fallback
- **WHEN** the ASDLC source path is unreachable, the bound worktree is missing an upstream, or the binding metadata is invalid
- **THEN** orchestrator exits non-zero with the existing fail-fast preflight error
- **AND** orchestrator does not offer a standalone or local-runtime-only execution path
- **AND** error messages do not reference any `--standalone` flag
