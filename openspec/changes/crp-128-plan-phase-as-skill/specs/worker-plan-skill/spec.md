## ADDED Requirements

### Requirement: Skill directory structure
The `yasdef-worker-plan` Codex skill SHALL be located at `ai/codex/skills/yasdef-worker-plan/` and SHALL contain `SKILL.md`, `scripts/build_plan_context.py`, `scripts/check_planning_readiness.py`, `scripts/sync_step_lars.py`, `assets/step_plan_TEMPLATE.md`, and `assets/step_plan_GOLDEN_EXAMPLE.md`.

#### Scenario: Skill files are present after creation
- **WHEN** the change is implemented
- **THEN** all required skill files exist under `ai/codex/skills/yasdef-worker-plan/`

### Requirement: Skill installation via init script
`init_asdlc_worker.sh` SHALL install `ai/codex/skills/yasdef-worker-plan/` into the worker project at `.codex/skills/yasdef-worker-plan` and SHALL add the installed path to `.git/info/exclude` in the worker project.

#### Scenario: Worker init installs the planning skill
- **WHEN** `init_asdlc_worker.sh` runs on a worker project
- **THEN** `.codex/skills/yasdef-worker-plan/` is present in the worker project
- **THEN** `.codex/skills/yasdef-worker-plan` appears in the worker project's `.git/info/exclude`

### Requirement: Skill explicit input contract
`SKILL.md` SHALL require all of the following inputs to be explicitly provided: step id, feature id, branch, design artifact path, step plan output path, runtime implementation plan path, open-questions file path, and blockers file path. If any required input is missing, inconsistent, or points to a missing required file, the skill SHALL stop and ask for explicit instructions without inferring replacement values.

#### Scenario: Missing design artifact blocks planning
- **WHEN** the design artifact path is not provided or the file does not exist
- **THEN** the skill stops and asks for explicit instructions rather than proceeding

#### Scenario: All inputs provided allows skill to proceed
- **WHEN** all required inputs are present and the design artifact file exists
- **THEN** the skill proceeds to run context assembly

### Requirement: Orchestrator planning loop
`ai_plan.sh` SHALL run the planning phase as a loop: invoke the `yasdef-worker-plan` skill with a compact variable-only prompt, then run `check_planning_readiness.py` and inspect per-step ledger files without invoking the model; if `check_planning_readiness.py` exits `0` AND both ledger files are empty, the loop terminates; otherwise the skill is invoked again for the next iteration.

#### Scenario: Loop terminates when readiness passes and ledgers are clean
- **WHEN** `check_planning_readiness.py` exits `0` and both per-step ledger files are empty after a skill session
- **THEN** `ai_plan.sh` exits the loop and emits the planning completion line

#### Scenario: Loop re-invokes when ledgers have entries
- **WHEN** `check_planning_readiness.py` exits `0` but a ledger file contains open entries after a skill session
- **THEN** `ai_plan.sh` invokes the skill again for the next iteration

#### Scenario: Loop re-invokes when readiness fails
- **WHEN** `check_planning_readiness.py` exits non-zero after a skill session
- **THEN** `ai_plan.sh` invokes the skill again for the next iteration

### Requirement: Orchestrator compact prompt
The orchestrator planning phase SHALL invoke the `yasdef-worker-plan` skill using a compact prompt that passes only variable values (step, feature id, branch, design artifact path, step plan output path, runtime implementation plan path, open-questions file path, blockers file path). Planning rules SHALL NOT be duplicated in the orchestrator prompt.

#### Scenario: Orchestrator prompt contains only variables
- **WHEN** the planning phase runs
- **THEN** the orchestrator writes a prompt that names `yasdef-worker-plan` and lists explicit variable assignments only

### Requirement: Context builder hard-fails on missing design artifact
`build_plan_context.py` SHALL exit with a non-zero code and a clear error message when the design artifact path is missing or the file is empty. It SHALL NOT infer a substitute design path from the runtime environment.

#### Scenario: Missing design artifact causes immediate failure
- **WHEN** `build_plan_context.py` is invoked with a design path that does not exist
- **THEN** the script exits non-zero with a descriptive error message

### Requirement: Skill session workflow
`SKILL.md` SHALL instruct the model to execute each planning session in three ordered phases: (1) read per-step ledger files and design Things to Decide, resolve all open questions and decisions with the user one-by-one; (2) update or generate `## Plan (ordered)` and `## Functional Requirements` based on resolved decisions; (3) read relevant repo files, analyse them against the current plan, resolve self-contained gaps in place, and write only gaps requiring user input to ledger files. The skill SHALL exit after phase 3 without looping internally.

#### Scenario: Session resolves open questions before writing plan
- **WHEN** the per-step open-questions file contains entries at session start
- **THEN** the skill resolves them with the user before updating the plan

#### Scenario: Existing FRs re-validated after phase 1 on update iterations
- **WHEN** phase 1 resolves one or more questions on an iteration where a step plan already exists
- **THEN** the skill re-reads all existing FRs against the design's `## Selected EARS Requirements` before writing phase 2, updating any FR whose wording depended on a decision that changed

#### Scenario: Session writes unresolved gaps to ledger files on exit
- **WHEN** the repo analysis identifies a gap that requires user input
- **THEN** the skill writes it to the appropriate per-step ledger file before exiting

#### Scenario: Session resolves self-contained gaps in place
- **WHEN** the repo analysis identifies a gap the model can resolve without user input
- **THEN** the plan is updated in the same session and nothing is written to ledger files

### Requirement: Per-step open-questions and blocker files
`build_plan_context.py` SHALL initialize the per-step open-questions file and per-step blockers file if either does not exist on first invocation for a step. Both files SHALL follow the same directory-per-type pattern as `step_designs/` and `step_plans/`: open-questions files under `step_open_questions/step-<step>-<feature-id>-open-questions.md` and blocker files under `step_blockers/step-<step>-<feature-id>-blockers.md`. The corresponding layout variables (`ASDLC_STEP_OPEN_QUESTIONS_DIR`, `ASDLC_STEP_BLOCKERS_DIR`) SHALL be added to `runtime_layout.sh`. `check_planning_readiness.py` SHALL treat both files as empty (clean) when they do not exist or contain no active entries.

#### Scenario: Per-step ledger files initialized on first invocation
- **WHEN** `build_plan_context.py` runs and the ledger files do not exist
- **THEN** both files are created as empty files before context is emitted

#### Scenario: Readiness treats missing ledger files as clean
- **WHEN** `check_planning_readiness.py` runs and a ledger file does not exist
- **THEN** that ledger is treated as clean (no entries)

### Requirement: Context builder assembles structured planning context
`build_plan_context.py` SHALL read the complete design artifact and extract and label all of the following sections when present: Target Bullets, Selected EARS Requirements, First-Feature Bootstrap, Things to Decide, Applicable AGENTS.md Constraints, Applicable User Review Rules, Applicable ADR Shortlist, and Linked Artifacts. It SHALL also include the current step section from the runtime implementation plan, the contents of the per-step open-questions and blockers files, and the current step plan content.

#### Scenario: Context builder extracts required design sections
- **WHEN** `build_plan_context.py` runs with a complete design artifact
- **THEN** the printed context contains labeled sections for all design sections present in the artifact

#### Scenario: Context builder includes implementation plan step section
- **WHEN** `build_plan_context.py` runs with a valid runtime plan path
- **THEN** the printed context includes the current step section from `implementation_plan.md`

### Requirement: Context builder initializes missing step plan from template
`build_plan_context.py` SHALL initialize the step plan file from `assets/step_plan_TEMPLATE.md` when the step plan output file does not exist. It SHALL NOT silently leave required placeholders unresolved after initialization.

#### Scenario: Missing step plan is initialized from template
- **WHEN** `build_plan_context.py` runs and the step plan output file does not exist
- **THEN** the step plan output file is created from `assets/step_plan_TEMPLATE.md`

### Requirement: Readiness gate validates planning closure
`check_planning_readiness.py` serves a dual role: orchestrator loop termination condition (called by `ai_plan.sh` after each skill exit) and model-callable validation inside the skill before the session exits. It SHALL validate all of the following and exit `0` only when all pass: design artifact exists; step plan exists; forbidden sections (`## Target Bullets`, `## Requirement Tags`) are absent from the step plan; required sections (`## Plan (ordered)`, `## Functional Requirements (translated from design EARS)`) exist and are ordered correctly; `## Applicable UR Shortlist` is present and contains either `- None.` or no more than 8 `UR-xxxx` entries; every selected EARS item has at least one translated FR and every FR maps to exactly one EARS source; every design Things-to-Decide item has an explicit `Accepted`, `Deferred`, or `Blocked` outcome; when design records `Bootstrap required: yes` the step plan contains `## Scaffold Bootstrap Plan` with scaffold work before dependent implementation work.

#### Scenario: Readiness gate exits 0 for a complete step plan
- **WHEN** `check_planning_readiness.py` runs against a step plan that satisfies all gates
- **THEN** the script exits with code `0`

#### Scenario: Readiness gate exits 1 for a malformed step plan
- **WHEN** `check_planning_readiness.py` runs against a step plan missing required sections or containing forbidden sections
- **THEN** the script exits with code `1` and prints structured error messages

#### Scenario: Readiness gate exits 1 when design decisions are unresolved
- **WHEN** `check_planning_readiness.py` runs and a Things-to-Decide item has no explicit outcome
- **THEN** the script exits with code `1` naming the unresolved item

#### Scenario: Readiness gate exits 2 for invalid usage
- **WHEN** `check_planning_readiness.py` is invoked without required arguments
- **THEN** the script exits with code `2`

### Requirement: LAR sync mirrors design LAR block into step plan
`sync_step_lars.py` SHALL copy the `## Linked Artifacts (in scope)` block from the design artifact into the step plan when the design artifact contains that section. It SHALL be idempotent — running it twice SHALL produce the same result.

#### Scenario: LAR sync copies design LAR section to step plan
- **WHEN** the design artifact contains `## Linked Artifacts (in scope)` and `sync_step_lars.py` runs
- **THEN** the step plan contains the same LAR entries

#### Scenario: LAR sync is idempotent
- **WHEN** `sync_step_lars.py` runs twice on the same inputs
- **THEN** the step plan LAR section is identical after both runs

### Requirement: Test coverage for all planning skill scripts
All Python scripts in `ai/codex/skills/yasdef-worker-plan/scripts/` SHALL have test coverage under `tests/skills_python_scripts/`. Tests SHALL cover: worker init installs the skill; orchestrator planning phase writes a compact `yasdef-worker-plan` prompt; orchestrator loop re-invokes skill when readiness fails or ledgers are dirty; orchestrator loop terminates when readiness passes and ledgers are clean; missing design artifact blocks planning; context builder initializes per-step ledger files on first invocation; context builder initializes a missing step plan from skill assets; context builder extracts required design sections; context builder includes per-step ledger file contents; LAR sync mirrors the design LAR block; readiness gate rejects malformed step plans and unresolved decisions; readiness gate passes for a complete planning artifact; readiness gate treats missing ledger files as clean.

#### Scenario: Focused tests pass for all planning scripts
- **WHEN** the planning script tests run
- **THEN** all tests in `tests/skills_python_scripts/` related to planning pass

### Requirement: AI_DEVELOPMENT_PROCESS.md planning block replaced with skill pointer
`AI_DEVELOPMENT_PROCESS.md §2` SHALL replace its inline planning rules block with a pointer to `.codex/skills/yasdef-worker-plan/SKILL.md`. Cross-phase rules needed by later phases SHALL be retained.

#### Scenario: AI_DEVELOPMENT_PROCESS.md contains skill pointer for planning
- **WHEN** the change is implemented
- **THEN** `AI_DEVELOPMENT_PROCESS.md §2` references `yasdef-worker-plan/SKILL.md` rather than duplicating planning rules inline
