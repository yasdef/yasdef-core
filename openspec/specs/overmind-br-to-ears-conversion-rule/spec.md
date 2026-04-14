## ADDED Requirements

### Requirement: BR-to-EARS conversion SHALL be defined by one authoritative rule artifact
The system SHALL define structured BR to EARS conversion behavior in `overmind/rules/br_to_ears.md` as the single authoritative contract for this stage.

#### Scenario: Conversion rule is required for BR-to-EARS stage
- **WHEN** BR-to-EARS conversion is executed
- **THEN** conversion behavior SHALL be governed by `overmind/rules/br_to_ears.md`

### Requirement: Conversion output SHALL follow existing EARS template and golden example structure
`overmind/rules/br_to_ears.md` SHALL require generated output to align with `overmind/templates/reqirements_ears_TEMPLATE.md` and `overmind/golden_examples/reqirements_ears_GOLDEN_EXAMPLE.md` as the primary formatting baseline.

#### Scenario: Output format references canonical EARS artifacts
- **WHEN** conversion rules are applied
- **THEN** output SHALL preserve the established Requirement/NFR block structure used by the existing template and golden example

### Requirement: Conversion SHALL use structured BR facts and explicitly mark inference boundaries
The conversion rule SHALL require using facts from `<feature_path>/feature_br_summary.md` and SHALL allow only explicitly marked inferences where necessary.

#### Scenario: BR fact is directly available
- **WHEN** required behavior is stated in `feature_br_summary.md`
- **THEN** generated EARS statements SHALL use that fact without adding unsupported business behavior

#### Scenario: BR fact is ambiguous or partial
- **WHEN** conversion requires interpretation beyond explicit BR wording
- **THEN** the output SHALL mark inference boundaries explicitly or keep requirements narrower instead of inventing behavior

### Requirement: Conversion SHALL extract atomic requirement ingredients from structured BR content
The conversion rule SHALL define extraction guidance for actor, trigger, preconditions, expected behavior, rejection behavior, state/data effect, side effects, integration effect, and relevant NFR constraints.

#### Scenario: Structured BR item contains required conversion ingredients
- **WHEN** a BR item includes one or more conversion ingredients
- **THEN** conversion SHALL map those ingredients into Requirement/NFR blocks and EARS acceptance bullets deterministically

### Requirement: Conversion SHALL split mixed obligations into atomic Requirement/NFR blocks
When a single BR item combines independent obligations (success path, rejection path, permissions, side effects, persistence, integrations), conversion SHALL split them into separate atomic Requirement/NFR blocks as needed.

#### Scenario: BR item mixes success and rejection obligations
- **WHEN** one BR item includes both expected and rejection behavior
- **THEN** conversion SHALL separate independent obligations into distinct atomic blocks or distinct independent bullets

#### Scenario: BR item mixes behavior and non-functional constraint
- **WHEN** one BR item includes functional behavior and NFR constraints
- **THEN** conversion SHALL place NFR constraints in appropriate NFR blocks instead of embedding them as mixed functional obligations

### Requirement: Acceptance criteria SHALL use preferred EARS patterns and one obligation per bullet
The conversion rule SHALL allow only preferred EARS patterns (`When`, `If`, `While`, `Where`) and SHALL require one EARS obligation per acceptance-criteria bullet.

#### Scenario: Independent obligations are present
- **WHEN** multiple obligations are required
- **THEN** conversion SHALL emit separate bullets or separate Requirement/NFR blocks so each obligation remains independently testable

### Requirement: Conversion SHALL avoid implementation leakage and stage-inappropriate content
The conversion rule SHALL forbid leaking technical design details, architecture decisions, file paths, or roadmap planning logic into EARS requirement statements.

#### Scenario: Source material includes technical implementation hints
- **WHEN** implementation-specific details appear in input context
- **THEN** conversion SHALL keep generated EARS statements business-behavior focused and exclude implementation leakage

### Requirement: Conversion stage SHALL not start new clarification loops
The conversion rule SHALL prohibit initiating new user clarification questions during this stage.

#### Scenario: Input ambiguity cannot be resolved from BR source
- **WHEN** ambiguity remains unresolved in source BR content
- **THEN** conversion SHALL produce conservative output with explicit unresolved gaps instead of starting a user-question loop

### Requirement: Requirement numbering SHALL be deterministic and stable within current template structure
The conversion rule SHALL require deterministic numbering/order for generated Requirement/NFR blocks in alignment with the existing template structure.

#### Scenario: Same structured BR input is converted repeatedly
- **WHEN** conversion is rerun with materially unchanged BR input
- **THEN** requirement ordering and numbering SHALL remain stable

### Requirement: Conversion rule SHALL support runtime path bindings
The conversion rule SHALL treat runtime path bindings as authoritative for input/output targets and SHALL not assume fixed `overmind/product/...` paths.

#### Scenario: Conversion runs with `--feature_path` override
- **WHEN** runtime context provides a non-default feature root
- **THEN** conversion guidance SHALL target `<feature_path>/feature_br_summary.md` input and `<feature_path>/requirements_ears_feature.md` output for that invocation
