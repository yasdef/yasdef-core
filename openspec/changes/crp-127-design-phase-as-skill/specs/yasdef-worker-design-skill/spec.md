## ADDED Requirements

### Requirement: YASDEF worker design skill is provided as a Codex skill
The repository MUST provide a Codex skill named `yasdef-worker-design` under `ai/codex/skills/yasdef-worker-design`, and the skill MUST contain a `SKILL.md` file, deterministic Python scripts for context assembly/readiness validation, and design template/golden-example assets.

#### Scenario: Skill files exist in source
- **WHEN** the source repository is inspected
- **THEN** `ai/codex/skills/yasdef-worker-design/SKILL.md` exists
- **AND** `ai/codex/skills/yasdef-worker-design/scripts/build_design_context.py` exists
- **AND** `ai/codex/skills/yasdef-worker-design/scripts/check_design_readiness.py` exists
- **AND** `ai/codex/skills/yasdef-worker-design/assets/feature_design_TEMPLATE.md` exists
- **AND** `ai/codex/skills/yasdef-worker-design/assets/feature_design_GOLDEN_EXAMPLE.md` exists

### Requirement: Design context builder assembles step-scoped context
The design skill MUST include a Python context builder that reads the selected implementation plan, requirements EARS file, feature metadata, blockers, and open questions, initializes the design artifact from the skill template when missing, and prints step-scoped context plus the skill golden example for the model.

#### Scenario: Context builder initializes missing design artifact
- **WHEN** the context builder runs for a valid step with `--design-out <path>`
- **THEN** it creates the design artifact when absent
- **AND** the artifact includes required design sections from the skill feature design template
- **AND** the printed context includes the selected step section and matching EARS requirement blocks
- **AND** the printed context includes the skill feature design golden example

#### Scenario: Context builder surfaces linked artifacts
- **WHEN** selected EARS blocks reference `LAR-NNN` entries present in the `## Linked Artifacts` registry
- **THEN** the printed context includes an in-scope linked-artifact shortlist for those ids

### Requirement: Design readiness gate is skill-bundled Python
The design skill MUST include a Python readiness gate that exits `0` for ready design artifacts, exits `1` with structured errors for incomplete artifacts, and exits `2` for invalid usage.

#### Scenario: Required sections are missing
- **WHEN** a design artifact lacks `## Goal`, `## In Scope`, or `## Out of Scope`
- **THEN** the readiness gate exits `1`
- **AND** reports the missing section names

#### Scenario: Bootstrap handoff is unresolved
- **WHEN** a design artifact records `Bootstrap required: yes` but has a pending or missing planning handoff
- **THEN** the readiness gate exits `1`
- **AND** reports that a concrete planning handoff is required
