## 1. Add the design Codex skill

- [x] 1.1 Create `ai/codex/skills/yasdef-worker-design/SKILL.md`
- [x] 1.2 Add `scripts/build_design_context.py` for step context assembly and template initialization
- [x] 1.3 Add `scripts/check_design_readiness.py` for required-section/bootstrap validation
- [x] 1.4 Move `feature_design_TEMPLATE.md` and `feature_design_GOLDEN_EXAMPLE.md` into skill `assets/`
- [x] 1.5 Update context builder to initialize from the skill template and print the skill golden example

## 2. Install the skill into worker projects

- [x] 2.1 Update `ai/scripts/init_asdlc_worker.sh` to copy the skill into `<target>/.codex/skills/yasdef-worker-design`
- [x] 2.2 Ensure `.codex/skills/yasdef-worker-design` is ignored as generated target runtime content
- [x] 2.3 Remove legacy design shell helpers from source/runtime output

## 3. Route design through the skill

- [x] 3.1 Update `ai/scripts/orchestrator.sh` so design no longer invokes `ai_design.sh`
- [x] 3.2 Make design prompt/log output call `yasdef-worker-design` with selected step, feature id, branch, and artifact paths
- [x] 3.3 Preserve planning and later phase behavior

## 4. Update process documentation

- [x] 4.1 Replace the detailed design workflow block in `ai/AI_DEVELOPMENT_PROCESS.md` with a reference to `.codex/skills/yasdef-worker-design`

## 5. Add and update tests

- [x] 5.1 Add Python-script tests under `tests/skills_python_scripts`
- [x] 5.2 Update worker initialization tests for skill installation and legacy design helper exclusion
- [x] 5.3 Update orchestrator design routing tests for skill prompt behavior
- [x] 5.4 Run focused tests and fix regressions
