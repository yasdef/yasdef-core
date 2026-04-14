## ADDED Requirements

### Requirement: Step-3 SHALL use one canonical EARS structure baseline
The system SHALL treat `overmind/templates/reqirements_ears_TEMPLATE.md` as the canonical Step-3 output template and `overmind/golden_examples/reqirements_ears_GOLDEN_EXAMPLE.md` as the canonical Step-3 example.

#### Scenario: Step-3 guidance is evaluated
- **WHEN** Step-3 BR-to-EARS guidance is authored or updated
- **THEN** the guidance SHALL preserve the existing template/example section structure as the output baseline

### Requirement: Step-3 assets SHALL avoid parallel output formats
The system SHALL NOT introduce a second Step-3 EARS artifact format that competes with the canonical template/example contract.

#### Scenario: New format proposal is introduced for Step-3
- **WHEN** a Step-3 change proposes alternate structure for EARS output
- **THEN** the change SHALL be rejected unless it updates the canonical template/example baseline directly

### Requirement: BR-to-EARS rule SHALL explicitly bind output to canonical assets
The system SHALL require `overmind/rules/br_to_ears.md` to instruct model output to follow the canonical template and golden example structure.

#### Scenario: Conversion rule is used for generation
- **WHEN** BR-to-EARS conversion executes using `br_to_ears.md`
- **THEN** output guidance SHALL reference and follow canonical Step-3 assets instead of inventing structure

### Requirement: Atomicity guidance SHALL be explicit and deterministic
The system SHALL require one EARS obligation per acceptance-criteria bullet and SHALL require splitting independent obligations into separate Requirement/NFR blocks where appropriate.

#### Scenario: Mixed obligation is present in source BR content
- **WHEN** one source statement includes independent happy-path, rejection, permission, side-effect, integration, or NFR obligations
- **THEN** Step-3 guidance SHALL require decomposition so each independent obligation is represented atomically

### Requirement: Clarifications SHALL remain helper-compatible
The system SHALL keep numbering and verification clarifications deterministic and compatible with existing Step-3 helper expectations.

#### Scenario: Clarification text is added to template or example
- **WHEN** deterministic wording or ordering guidance is refined
- **THEN** refinements SHALL preserve compatibility with existing helper checks and current canonical structure
