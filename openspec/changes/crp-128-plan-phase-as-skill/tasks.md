## 1. Skill Directory and Assets

- [ ] 1.1 Create `ai/codex/skills/yasdef-worker-plan/` directory structure (`scripts/`, `assets/`)
- [ ] 1.2 Move or create `assets/step_plan_TEMPLATE.md` with all required planning section placeholders
- [ ] 1.3 Move or create `assets/step_plan_GOLDEN_EXAMPLE.md` as style/completeness reference
- [ ] 1.4 Write `SKILL.md` with the model-facing three-phase session workflow (resolve questions → update plan → analyse gaps and write ledger), input contract, gates, golden-example usage instructions, and exit-after-gap-write discipline; include explicit instruction that after phase 1 the model re-reads all existing FRs against the design's `## Selected EARS Requirements` before writing phase 2, to catch any FR whose wording depended on a decision that just changed

## 2. Python Scripts

- [ ] 2.1 Implement `scripts/build_plan_context.py` — accepts `--step`, `--feature-id`, `--design`, `--plan-out`, `--runtime-plan`, `--open-questions`, `--blockers` arguments; emits EARS file path as pointer-only line; fails fast if design artifact is missing or empty
- [ ] 2.2 Add design section extraction to `build_plan_context.py` (Target Bullets, Selected EARS, Things to Decide, Bootstrap, AGENTS, UR, ADR, LAR)
- [ ] 2.3 Add step plan initialization from `assets/step_plan_TEMPLATE.md` with placeholder-hit assertions to `build_plan_context.py`
- [ ] 2.4 Add current step section reading from runtime implementation plan to `build_plan_context.py`; read per-step open-questions and blockers files (from `--open-questions` and `--blockers` paths) and include their contents in context output
- [ ] 2.7 Add per-step ledger file initialization to `build_plan_context.py`: create `step_open_questions/` and `step_blockers/` directories if absent; create empty ledger files at the paths passed via `--open-questions` and `--blockers` if they do not exist
- [ ] 2.8 Add `ASDLC_STEP_OPEN_QUESTIONS_DIR` and `ASDLC_STEP_BLOCKERS_DIR` to `runtime_layout.sh` following the `step_designs`/`step_plans` pattern
- [ ] 2.5 Implement `scripts/check_planning_readiness.py` — validates all planning closure gates; exits `0` (ready), `1` (gate failure with structured errors), or `2` (usage/system error)
- [ ] 2.6 Implement `scripts/sync_step_lars.py` — copies `## Linked Artifacts (in scope)` block from design artifact to step plan; idempotent

## 3. Install and Migration

- [ ] 3.1 Update `init_asdlc_worker.sh` to install `.codex/skills/yasdef-worker-plan` from `ai/codex/skills/yasdef-worker-plan`
- [ ] 3.2 Add `.codex/skills/yasdef-worker-plan` to `.git/info/exclude` handling in `init_asdlc_worker.sh`
- [ ] 3.3 Replace `run_planning_phase` detailed prompt block in `ai/scripts/ai_plan.sh` with a compact skill-invocation prompt (variables only, naming `yasdef-worker-plan`); derive ledger file paths from `$ASDLC_STEP_OPEN_QUESTIONS_DIR` and `$ASDLC_STEP_BLOCKERS_DIR` using the `step-<step>-<feature-id>` naming convention and pass them as `--open-questions` and `--blockers`
- [ ] 3.4 Implement orchestrator loop in `ai_plan.sh`: after each skill exit run `check_planning_readiness.py`; inspect per-step open-questions and blockers files; exit loop only when readiness exits `0` AND both files are clean; otherwise re-invoke skill
- [ ] 3.5 Replace inline planning rules block in `AI_DEVELOPMENT_PROCESS.md §2` with a pointer to `yasdef-worker-plan/SKILL.md`; retain cross-phase rules needed by later phases

## 4. Tests

- [ ] 4.1 Add test: worker init installs `.codex/skills/yasdef-worker-plan`
- [ ] 4.2 Add test: orchestrator planning phase writes a compact `yasdef-worker-plan` prompt (no inline planning rules)
- [ ] 4.2b Add test: orchestrator loop re-invokes skill when readiness exits non-zero
- [ ] 4.2c Add test: orchestrator loop re-invokes skill when a ledger file has entries after skill exit
- [ ] 4.2d Add test: orchestrator loop terminates when readiness exits `0` and both ledger files are clean
- [ ] 4.3 Add test: missing design artifact blocks `build_plan_context.py` with non-zero exit
- [ ] 4.4 Add test: `build_plan_context.py` initializes per-step ledger files when they do not exist
- [ ] 4.4b Add test: `build_plan_context.py` initializes missing step plan from `assets/step_plan_TEMPLATE.md`
- [ ] 4.5 Add test: `build_plan_context.py` extracts required design sections
- [ ] 4.5b Add test: `build_plan_context.py` includes per-step ledger file contents in context output
- [ ] 4.6 Add test: `sync_step_lars.py` mirrors design LAR block into step plan; idempotent
- [ ] 4.7 Add test: `check_planning_readiness.py` exits `1` for malformed step plans and unresolved design decisions
- [ ] 4.8 Add test: `check_planning_readiness.py` exits `0` for a complete planning artifact
- [ ] 4.8b Add test: `check_planning_readiness.py` treats missing ledger files as clean
- [ ] 4.9 Run `tests/skills_python_scripts/` focused tests and `git diff --check`
