## MODIFIED Requirements

### Requirement: Design readiness is enforced before planning handoff
Design readiness MUST be validated by the `yasdef-worker-design` skill's bundled Python readiness gate before design handoff, while planning continues to require the design artifact before it runs.

#### Scenario: Skill readiness gate is referenced by design workflow
- **WHEN** the design skill is used
- **THEN** its workflow instructs the model to run `scripts/check_design_readiness.py` against the design artifact before finishing

#### Scenario: Planning still requires design artifact
- **WHEN** planning starts for a step
- **THEN** the expected design artifact remains the scope contract for planning
- **AND** planning behavior outside design readiness ownership remains unchanged
