## Why

The planning phase is currently driven by inline prompt generation in `ai/scripts/ai_plan.sh`, which duplicates planning rules into the orchestrator and makes them hard to update independently. Converting to a repo-provided Codex skill moves planning instructions, context assembly, readiness validation, and LAR sync into a versioned, installable skill — matching the design-phase pattern established by `yasdef-worker-design`.

## What Changes

- Add `ai/codex/skills/yasdef-worker-plan/` with `SKILL.md`, Python scripts (`build_plan_context.py`, `check_planning_readiness.py`, `sync_step_lars.py`), and assets (`step_plan_TEMPLATE.md`, `step_plan_GOLDEN_EXAMPLE.md`)
- Wrap the planning phase in `ai/scripts/ai_plan.sh` as an orchestrator loop: invoke `yasdef-worker-plan` skill with a compact variable-only prompt, then machine-check plan readiness and ledger state; repeat until both pass
- Introduce per-step open-questions and blocker files (`step_open_questions/step-<step>-<feature-id>-open-questions.md`, `step_blockers/step-<step>-<feature-id>-blockers.md`) as machine-readable loop ledgers, following the same directory-per-type pattern as `step_designs/` and `step_plans/`, replacing the current section-based shared files for new planning runs
- Move `step_plan_TEMPLATE.md` and `step_plan_GOLDEN_EXAMPLE.md` into the skill `assets/` directory
- Update `init_asdlc_worker.sh` to install `.codex/skills/yasdef-worker-plan` alongside existing skills
- Add test coverage under `tests/skills_python_scripts/` for all new Python scripts
- Replace the detailed planning block in `AI_DEVELOPMENT_PROCESS.md` with a pointer to the skill's `SKILL.md`
- Remove or retire legacy planning runtime scripts once the skill fully replaces them

## Capabilities

### New Capabilities
- `worker-plan-skill`: Installable Codex skill that owns one planning iteration — resolves open questions and design decisions with the user, updates `## Plan (ordered)` and `## Functional Requirements`, analyses the repo against the current plan to identify gaps requiring user input, writes findings to per-step ledger files, and exits; the orchestrator loop re-invokes until plan readiness passes and ledger files are clean

### Modified Capabilities

## Impact

- `ai/scripts/ai_plan.sh`: orchestrator planning prompt becomes compact (variables only)
- `ai/scripts/init_asdlc_worker.sh`: installs new skill directory into `.codex/skills/`
- `ai/AI_DEVELOPMENT_PROCESS.md §2`: planning rules pointer replaces inline block
- `tests/skills_python_scripts/`: new focused tests for planning scripts
- Worker projects: `init_asdlc_worker.sh` install propagates the skill to `.codex/skills/yasdef-worker-plan`
