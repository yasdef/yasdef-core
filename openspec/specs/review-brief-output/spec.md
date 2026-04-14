## ADDED Requirements

### Requirement: Implementation phase does not emit Review Brief
Implementation-phase output MUST NOT require or emit Review Brief content as part of implementation handoff.

#### Scenario: Implementation handoff excludes Review Brief
- **WHEN** implementation phase reaches handoff completion
- **THEN** output does not include a Review Brief requirement and does not instruct emission in implementation phase

## MODIFIED Requirements

### Requirement: Review Brief is emitted at implementation-to-review handoff
At the beginning of User Review phase, before requesting review feedback, the user_review model response MUST emit a Review Brief.

#### Scenario: Brief appears before review interaction
- **WHEN** User Review phase starts for a step
- **THEN** the response includes a Review Brief before requesting the next user review item
