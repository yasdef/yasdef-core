## Context

`ai_design.sh` currently performs three responsibilities at once: branch setup, context assembly, and prompt generation. The new design-phase contract separates those responsibilities:

- shell/orchestrator keeps runtime routing, branch setup, log capture, and model invocation;
- `yasdef-worker-design` owns design-phase instructions and model behavior;
- bundled Python scripts own deterministic context assembly and readiness validation.
- skill assets own the design template and golden example used for deterministic design artifact shape.

The target runtime already supports project-local Codex skills under `.codex/skills`, so the worker init script can deploy the skill alongside `.asdlc_worker` without changing downstream planning/implementation phases.

## Goals / Non-Goals

**Goals:**
- Provide a repo-owned Codex skill at `ai/codex/skills/yasdef-worker-design`.
- Move `feature_design_TEMPLATE.md` and `feature_design_GOLDEN_EXAMPLE.md` into the skill assets and use them from there.
- Keep design interactive: the model asks the user about unresolved design choices instead of only consuming a static prompt.
- Preserve current feature/step routing and branch naming for design (`step-<step>-<feature>-plan`).
- Remove legacy design shell helpers from the source/runtime path.
- Test skill Python scripts in this repo under `tests/skills_python_scripts`.

**Non-Goals:**
- Rewrite planning, implementation, user review, audit, or post-review behavior.
- Add new user-facing CLI flags.
- Change model configuration format.

## Decisions

**Skill layout.**
The skill lives at `ai/codex/skills/yasdef-worker-design` with:
- `SKILL.md` for trigger metadata and phase workflow;
- `scripts/build_design_context.py` for deterministic context assembly and design artifact initialization;
- `scripts/check_design_readiness.py` for required-section/bootstrap validation.
- `assets/feature_design_TEMPLATE.md` and `assets/feature_design_GOLDEN_EXAMPLE.md` for deterministic design artifact structure and style.

**Design template/example ownership.**
The design template and golden example are no longer installed as generic `.asdlc_worker/templates` or `.asdlc_worker/golden_examples` assets. `build_design_context.py` reads the template from its skill `assets/` directory when initializing a missing design artifact and prints the skill golden example in the context pack so the model has a local style reference.

**Installer behavior.**
`init_asdlc_worker.sh` creates `<target>/.codex/skills` if needed and replaces only the `yasdef-worker-design` skill directory from source. The installed skill is added to `.git/info/exclude` so first-time install stashing does not remove it as unrelated untracked work.

**Legacy design helpers.**
No backwards compatibility path is kept. The source/runtime design shell helpers are removed:
- `.asdlc_worker/scripts/ai_design.sh`
- `.asdlc_worker/scripts/helpers/check_design_readiness.sh`

**Orchestrator design phase.**
The orchestrator still resolves the step, design output path, feature id, branch name, prompt/log path, and model config. It writes a compact prompt file only for logging/debug parity, then invokes the model with prompt text instructing it to use `yasdef-worker-design`. It does not invoke `ai_design.sh` or recreate design-phase rule logic.

**Process document.**
`AI_DEVELOPMENT_PROCESS.md` keeps design as mandatory but delegates detailed design workflow to `.codex/skills/yasdef-worker-design/SKILL.md`; planning and later sections remain unchanged.

## Risks / Trade-offs

[Skill not installed or unavailable] -> The orchestrator prompt explicitly names the expected skill path and the installer deploys it by default. A missing skill will surface immediately in the model session instead of silently falling back to legacy design generation.

[Existing tests assume `ai_design.sh` runtime installation] -> Update install/routing tests to assert the new contract and add direct Python-script coverage for the skill.

[Python dependency friction] -> The bundled scripts use Python standard library only for now and are executed with `uv run python`. The orchestrator hard-checks that `uv` is installed before starting work.
