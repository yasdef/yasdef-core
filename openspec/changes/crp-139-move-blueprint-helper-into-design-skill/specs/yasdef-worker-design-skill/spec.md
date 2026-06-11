## ADDED Requirements

### Requirement: Design skill ships a blueprint-finder Python helper inside its own scripts/ directory

The `yasdef-worker-design` skill SHALL ship a Python script at `ai/skills/yasdef-worker-design/scripts/find_blueprints.py` that performs class-aware blueprint discovery for the design phase.

The script SHALL:

- Resolve the feature directory by preferring `cwd` when it contains both `implementation_plan.md` and (`requirements_ears.md` OR `reqirements_ears.md` — the typo fallback is preserved); otherwise fall back to `dirname(os.environ["ASDLC_RUNTIME_PLAN_PATH"])` when that env var is set and the resolved path is a directory.
- Read the `class` scalar from `.asdlc_worker/project_overmind.yaml` in the worker repo, handling single-quoted, double-quoted, and unquoted YAML values, and stripping trailing `# comment` content from the line.
- Normalize the class string using the map: `back|backend|api|server → back`; `front|frontend|front-end|web|ui → front`; `mobile|ios|android|react-native → mobile`. Any other value resolves to an empty string (unresolved).
- Search the parent of the feature directory non-recursively for files matching `project_stack_blueprint_*.md`, sorted lexically (LC_ALL=C equivalent).
- Partition the matched blueprints into "relevant" (basename contains a class-substring for the normalized class: `back|backend` for back; `front|frontend|web` for front; `mobile|ios|android` for mobile) and "irrelevant" (everything else).
- Emit a single human-readable text block to stdout containing: the `Blueprint helper result` preamble; the five labeled lines (`Feature folder:`, `Project-level search root:`, `Binding file:`, `Raw project class:`, `Normalized project class:`); the `All blueprint candidates:` block; the per-class `Relevant blueprint candidates for class <X>:` and `Irrelevant blueprint candidates for class <X>:` blocks; and the final `Relevant blueprint result:` summary line.
- Exit with code 0 in all successful paths (including the no-class-resolvable and no-blueprints-found paths). Exit non-zero only when the feature directory cannot be resolved.

#### Scenario: Feature directory resolved from cwd

- **WHEN** the script is invoked from a directory that contains `implementation_plan.md` and `requirements_ears.md`
- **THEN** the resolved feature directory is the cwd, regardless of the `ASDLC_RUNTIME_PLAN_PATH` environment variable

#### Scenario: Feature directory resolved from ASDLC_RUNTIME_PLAN_PATH

- **WHEN** the cwd does not contain the feature marker files and `ASDLC_RUNTIME_PLAN_PATH` is set to a path whose dirname exists
- **THEN** the resolved feature directory is the dirname of `ASDLC_RUNTIME_PLAN_PATH`

#### Scenario: Feature directory cannot be resolved

- **WHEN** neither the cwd nor `ASDLC_RUNTIME_PLAN_PATH` yields a feature directory
- **THEN** the script exits non-zero with the message `Blueprint lookup failed: run this helper from an ASDLC feature folder with implementation_plan.md and requirements_ears.md, or ensure ASDLC_RUNTIME_PLAN_PATH is set.`

#### Scenario: Class normalization

- **WHEN** the raw class value in the binding file is any of `back`, `backend`, `api`, `server` (case-insensitive)
- **THEN** the normalized class is `back`

#### Scenario: Unresolved class produces an empty relevant list

- **WHEN** the raw class value does not match any known alias
- **THEN** the output prints `Normalized project class: unresolved` and the `Relevant blueprint result:` summary indicates no class-matching blueprint found

#### Scenario: Class-substring partition of blueprints

- **WHEN** the normalized class is `back` and the parent directory contains `project_stack_blueprint_back.md` and `project_stack_blueprint_front.md`
- **THEN** the back blueprint appears under `Relevant blueprint candidates for class back:` and the front blueprint appears under `Irrelevant blueprint candidates for class back:`

### Requirement: Design SKILL.md invokes the in-skill blueprint helper

The design skill's `SKILL.md` SHALL instruct the model to invoke the blueprint helper as `uv run python .claude/skills/yasdef-worker-design/scripts/find_blueprints.py` from the ASDLC feature folder context. The path SHALL use the `.claude/skills/` prefix, matching the existing convention used by the skill's other internal-script invocations (`build_design_context.py`, `check_design_readiness.py`).

The SKILL.md SHALL NOT reference any path under `.asdlc_worker/scripts/` for blueprint discovery.

#### Scenario: SKILL.md references the new in-skill helper

- **WHEN** an operator opens `ai/skills/yasdef-worker-design/SKILL.md`
- **THEN** the file contains a line instructing the model to run `uv run python .claude/skills/yasdef-worker-design/scripts/find_blueprints.py` for stack/architecture guidance, with no remaining reference to `.asdlc_worker/scripts/helpers/helper_find_blueprints.sh`

## REMOVED Requirements

### Requirement: Blueprint helper ships as a bash script under .asdlc_worker/scripts/helpers/

**Reason:** The bash helper at `ai/scripts/helpers/helper_find_blueprints.sh` is deleted by this change. Its logic is ported in full to a Python script inside the design skill bundle (`ai/skills/yasdef-worker-design/scripts/find_blueprints.py`), and the design skill's SKILL.md is updated to invoke the new path. No skill or orchestrator script references the removed bash helper after this change.

**Migration:** Operators who today invoke the bash helper directly for debugging (`bash .asdlc_worker/scripts/helpers/helper_find_blueprints.sh`) switch to invoking the new Python script from the same feature-directory context (`uv run python .claude/skills/yasdef-worker-design/scripts/find_blueprints.py`). The Python script preserves the bash helper's output format, class normalization rules, search semantics, and exit-code behavior.
