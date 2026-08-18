## Purpose

Enables GitHub Copilot CLI to execute every Yasdef model-driven phase through the same configurable, interactive, skill-driven workflow as the existing model runners.

## ADDED Requirements

### Requirement: GitHub Copilot CLI is a supported phase runner
Yasdef SHALL recognize the exact `copilot` command value in `.asdlc_worker/setup/models.md` for any model-driven phase and SHALL select the GitHub Copilot CLI runner for that phase. Copilot phases SHALL use the same canonical phase order, rendered phase prompt, and completion processing as other supported runners.

#### Scenario: One phase selects Copilot
- **WHEN** a valid complete model configuration assigns `copilot` to one model-driven phase
- **THEN** Yasdef selects the GitHub Copilot CLI runner when that phase executes
- **THEN** the other phases continue to use their independently configured runners

#### Scenario: Every model-driven phase selects Copilot
- **WHEN** a valid complete model configuration assigns `copilot` to `design`, `planning`, `implementation`, `user_review`, and `ai_audit`
- **THEN** Yasdef selects the GitHub Copilot CLI runner for all five phases
- **THEN** `post_review` remains worker-managed and does not invoke Copilot

### Requirement: Copilot receives an interactive initial prompt
For a Copilot phase, Yasdef SHALL invoke `copilot` with `--model <configured-model>`, followed by configured extra arguments in their original order, followed by `-i <phase-prompt>`. The complete rendered phase prompt MUST be passed as one argument to `-i`, causing Copilot to enter interactive mode and execute that prompt automatically.

#### Scenario: Copilot invocation without extra arguments
- **WHEN** a phase is configured as `design | copilot | claude-haiku-4.5`
- **THEN** its runner argv is exactly `copilot --model claude-haiku-4.5 -i <phase-prompt>` element-by-element

#### Scenario: Copilot invocation preserves extra arguments
- **WHEN** a phase is configured as `implementation | copilot | claude-haiku-4.5 | --effort | high`
- **THEN** its runner argv is exactly `copilot --model claude-haiku-4.5 --effort high -i <phase-prompt>` element-by-element
- **THEN** Yasdef does not reinterpret, drop, or reorder the configured extra arguments

### Requirement: Copilot uses the shared interactive process path
Copilot phases SHALL request a TTY and log capture through Yasdef's shared model-process execution path. When Yasdef is attached to a terminal, Copilot's interactive UI SHALL receive a pseudo-TTY and the session output SHALL be captured at the normal per-phase log path.

#### Scenario: Copilot phase runs from a terminal
- **WHEN** Yasdef dispatches a Copilot phase while standard output is attached to a terminal
- **THEN** the Copilot process receives the same TTY-preserving wrapper used by the existing interactive runners
- **THEN** session output is captured in the phase log

#### Scenario: Copilot process exits unsuccessfully
- **WHEN** the Copilot process exits with a non-zero status before the phase completes
- **THEN** Yasdef reports the phase execution failure through its existing process-failure path
- **THEN** Yasdef does not mark the phase complete

### Requirement: Copilot reuses the canonical phase skills
Yasdef SHALL use the existing `yasdef-worker-*` phase prompts and installed skill bundles for Copilot. Supporting Copilot MUST NOT introduce a second Copilot-specific copy of phase workflow rules or alter phase prompt content based on runner choice.

#### Scenario: Freshly initialized worker runs a Copilot phase
- **WHEN** a worker initialized by Yasdef runs a phase configured with `copilot`
- **THEN** the phase prompt identifies the same canonical `yasdef-worker-*` skill used by Codex and Claude
- **THEN** Copilot can discover the installed skill from a project skill directory already produced by Yasdef init

#### Scenario: A phase changes runner
- **WHEN** an operator changes a phase command between `codex`, `claude`, and `copilot` without changing the phase inputs
- **THEN** Yasdef renders the same phase prompt body for each runner

### Requirement: New workers default to Copilot with Claude Haiku 4.5
The packaged `.asdlc_worker/setup/models.md` SHALL configure `copilot` with model `claude-haiku-4.5` and no extra arguments for all five model-driven phases. Its guidance SHALL also include a full commented five-phase Copilot/Haiku configuration block, matching the format of the existing commented Claude configuration block. Operators SHALL remain able to replace the command, model, and extra arguments independently for each phase using the existing configuration format.

#### Scenario: New worker receives packaged defaults
- **WHEN** Yasdef initializes a worker that has no existing model configuration
- **THEN** `design`, `planning`, `implementation`, `user_review`, and `ai_audit` are each configured with command `copilot` and model `claude-haiku-4.5`
- **THEN** no extra arguments are configured for any of the five default rows

#### Scenario: Packaged guidance shows a complete Copilot example
- **WHEN** an operator reads the packaged `models.md` guidance
- **THEN** it contains commented example rows for all five model-driven phases using `copilot` and `claude-haiku-4.5`
- **THEN** each commented Copilot example row shows no extra arguments

#### Scenario: Operator mixes supported runners
- **WHEN** an operator replaces one or more packaged rows with valid `codex` or `claude` rows while keeping a complete five-phase configuration
- **THEN** Yasdef accepts the configuration
- **THEN** each phase uses its configured command and model

#### Scenario: Reinitialization encounters an operator-modified model configuration
- **WHEN** Yasdef reinitializes a worker whose installed model configuration differs from the previously installed manifest content
- **THEN** the operator-modified model configuration is preserved unless the operator explicitly forces replacement
