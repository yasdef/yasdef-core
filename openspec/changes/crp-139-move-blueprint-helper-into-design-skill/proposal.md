## Why

The design skill instructs models to run `.asdlc_worker/scripts/helpers/helper_find_blueprints.sh` at `ai/skills/yasdef-worker-design/SKILL.md:92`. The bash→Python orchestrator port planned in `design_docs/orchestrator_to_python_ref_plan.md` deletes `.asdlc_worker/scripts/` entirely — orchestrator code lives in the globally-installed `yasdef` CLI after migration. Once that lands, the design skill would instruct the LLM to call a file that no longer exists.

The helper has exactly one consumer (the design skill) and is a self-contained class-aware blueprint search over the parent project directory. Promoting it to a `yasdef find-blueprints` CLI subcommand would create CLI surface for zero reuse benefit. The cleaner placement is inside the design skill bundle, alongside its other internal Python scripts (`build_design_context.py`, `check_design_readiness.py`).

This change ports the bash helper to a Python script inside the design skill, updates the skill instruction to invoke the new path, and deletes the bash helper. After this CRP, no skill references `.asdlc_worker/scripts/helpers/` and the design skill's blueprint-discovery path no longer depends on the orchestrator script directory that the Python port removes.

## What Changes

- Add `ai/skills/yasdef-worker-design/scripts/find_blueprints.py` — direct Python port of `ai/scripts/helpers/helper_find_blueprints.sh` preserving the existing behavior: feature-directory resolution (cwd lookup + `ASDLC_RUNTIME_PLAN_PATH` fallback), `.asdlc_worker/project_overmind.yaml` class scalar read, class normalization (back/backend/api/server → back; front/frontend/web/ui → front; mobile/ios/android/react-native → mobile), `project_stack_blueprint_*.md` search under the parent directory, class-based path-substring filter, and the existing human-readable output format (preamble line + all-candidates list + relevant-candidates list + result summary).
- Update `ai/skills/yasdef-worker-design/SKILL.md:92` to replace the bash invocation with `uv run python .claude/skills/yasdef-worker-design/scripts/find_blueprints.py`, matching the prefix convention already used by sibling script invocations (`build_design_context.py`, `check_design_readiness.py`).
- Delete `ai/scripts/helpers/helper_find_blueprints.sh`. No deprecation window — the single consumer updates simultaneously with the deletion.
- Update `tests/ai_scripts/init_asdlc_worker_tests.sh` and any other tests asserting on the bash helper path.

## Capabilities

### Modified Capabilities

- `yasdef-worker-design-skill`: gains an internal `find_blueprints.py` and routes blueprint discovery through the skill bundle. No change to inputs, workflow contract, or sentinel completion semantics.
- `worker-runtime-bootstrap`: the bash helper stops shipping into target repos. No active install-list change needed because the helper rode in as part of the bulk `scripts/` directory copy; deleting the source file is sufficient. (The bulk `scripts/` copy itself is removed in the separate Python-port migration; that's out of scope here.)

## Impact

- `ai/skills/yasdef-worker-design/scripts/find_blueprints.py`: new file (Python port of the bash logic).
- `ai/skills/yasdef-worker-design/SKILL.md`: line 92 updated; rest of file unchanged.
- `ai/scripts/helpers/helper_find_blueprints.sh`: deleted.
- `tests/ai_scripts/init_asdlc_worker_tests.sh` and any sibling test files: assertions referencing the bash helper path updated or removed.
- `ai/scripts/orchestrator.sh`, `ai/scripts/post_review.sh`, `ai/scripts/init_asdlc_worker.sh`, `ai/scripts/register_worker.sh`, `ai/scripts/helpers/runtime_layout.sh`, `ai/scripts/helpers/build_phase_cmd.sh`: unchanged.
- `design_docs/orchestrator_to_python_ref_plan.md`: separate edit (drop `app/blueprint_finder.py`, `cli/find_blueprints.py`, and the `yasdef find-blueprints` CLI subcommand) — applied alongside this CRP but not part of its task list.
