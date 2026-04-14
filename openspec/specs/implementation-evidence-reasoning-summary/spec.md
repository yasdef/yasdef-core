## MODIFIED Requirements

### Requirement: Implementation output includes an Evidence Reasoning Summary after verification and tracking closure
The workflow MUST include an "Evidence Reasoning Summary" in `ai_audit` output immediately after `ai_audit` entry proof-check against `implementation_plan.md` target bullets and before deeper audit analysis.

#### Scenario: Summary appears at ai_audit entry handoff
- **WHEN** `ai_audit` starts for a step and executes target-bullet proof-check
- **THEN** the audit output includes an "Evidence Reasoning Summary" before broader audit findings

### Requirement: Summary provides per-bullet proof status for implemented targets
The summary MUST enumerate each target bullet from `implementation_plan.md` in scope for the step and MUST assign exactly one proof status of `PROVEN` or `NOT_PROVEN`.

#### Scenario: Each target bullet receives explicit status
- **WHEN** target bullets are evaluated at `ai_audit` entry
- **THEN** each in-scope target bullet appears once in the summary with either `PROVEN` or `NOT_PROVEN`

### Requirement: Proven bullets include complete evidence fields
Each bullet marked `PROVEN` MUST include code references (file path and key symbol), reachability from a concrete flow entrypoint, and test evidence via new/updated tests or explicit credible mapping to existing coverage.

#### Scenario: Proven bullet includes required evidence triplet
- **WHEN** a target bullet is marked `PROVEN`
- **THEN** its entry includes code references, reachability explanation, and test evidence or explicit credible mapping

### Requirement: Missing evidence forces NOT_PROVEN and unchecked tracking state
If any required evidence field is missing or uncertain, the bullet MUST be marked `NOT_PROVEN` and `ai_audit` MUST fail the entry proof gate before continuing to deeper analysis.

#### Scenario: Incomplete evidence blocks audit progression
- **WHEN** reachability or test evidence cannot be concretely identified for a target bullet
- **THEN** the summary marks the bullet as `NOT_PROVEN` and `ai_audit` does not proceed to deeper quality analysis

### Requirement: Reachability evidence prioritizes concrete entrypoints
Reachability notes for `PROVEN` bullets MUST identify concrete entrypoints first (controllers/handlers/jobs/UI actions), then supporting service and persistence flow as needed.

#### Scenario: Reachability starts from entrypoint
- **WHEN** the summary describes how implementation code is exercised in real flow
- **THEN** it names the concrete entrypoint before lower-layer implementation references

### Requirement: Summary remains compact and avoids speculative claims
The summary MUST use a compact, scannable bullet-list format and MUST NOT include speculative or guessed evidence claims.

#### Scenario: No-guess compact summary
- **WHEN** evidence reasoning is emitted
- **THEN** output is brief, bullet-structured, and excludes unsupported assertions
