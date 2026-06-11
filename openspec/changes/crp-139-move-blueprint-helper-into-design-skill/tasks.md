## 1. Port the helper logic to Python inside the design skill

- [x] 1.1 Create `ai/skills/yasdef-worker-design/scripts/find_blueprints.py` with the same shebang and code style as sibling scripts (`build_design_context.py`, `check_design_readiness.py`).
- [x] 1.2 Implement feature-directory resolution: prefer `cwd` when it contains both `implementation_plan.md` and (`requirements_ears.md` OR `reqirements_ears.md` — preserve the typo fallback from the bash); else use `dirname(os.environ["ASDLC_RUNTIME_PLAN_PATH"])` if set and exists; else die with the same message as the bash ("Blueprint lookup failed: run this helper from an ASDLC feature folder with implementation_plan.md and requirements_ears.md, or ensure ASDLC_RUNTIME_PLAN_PATH is set.").
- [x] 1.3 Implement YAML scalar read for `.asdlc_worker/project_overmind.yaml` `class` key, matching the bash awk reader's handling of single-quoted, double-quoted, and unquoted values; also strip trailing `# comment` content.
- [x] 1.4 Implement class normalization map identical to the bash: `back|backend|api|server → back`; `front|frontend|front-end|web|ui → front`; `mobile|ios/android|react-native → mobile`; anything else → empty string (unresolved).
- [x] 1.5 Implement blueprint search: non-recursive listing of `project_stack_blueprint_*.md` in `feature_dir/..`, sorted lexically (LC_ALL=C equivalent).
- [x] 1.6 Implement class-based filter using case-insensitive substring match on the basename, with the same substring lists per class as the bash `matches_class` function.
- [x] 1.7 Implement the human-readable output: `Blueprint helper result` preamble, the five labeled lines (`Feature folder:`, `Project-level search root:`, `Binding file:`, `Raw project class:`, `Normalized project class:`), the `All blueprint candidates:` block, the per-class `Relevant blueprint candidates for class <X>:` and `Irrelevant blueprint candidates for class <X>:` blocks, and the final `Relevant blueprint result:` summary line — preserving the bash's exit-0 behavior in all branches (no error exit even when no class is resolvable).

## 2. Update the design SKILL.md invocation

- [x] 2.1 Edit `ai/skills/yasdef-worker-design/SKILL.md:92`. Replace `When stack/architecture guidance is needed, run `.asdlc_worker/scripts/helpers/helper_find_blueprints.sh` from the ASDLC feature folder context where `implementation_plan.md` and `requirements_ears.md` live.` with `When stack/architecture guidance is needed, run `uv run python .claude/skills/yasdef-worker-design/scripts/find_blueprints.py` from the ASDLC feature folder context where `implementation_plan.md` and `requirements_ears.md` live.`. Preserve the rest of the line (the fallback instruction for missing class metadata).

## 3. Delete the bash helper

- [x] 3.1 `git rm ai/scripts/helpers/helper_find_blueprints.sh`.
- [x] 3.2 Verify no other file in `ai/`, `tests/`, or `openspec/` references `helper_find_blueprints` by name. Grep: `grep -rn 'helper_find_blueprints' .` should return only this CRP's own files after the deletion.

## 4. Update tests

- [x] 4.1 In `tests/ai_scripts/init_asdlc_worker_tests.sh`, remove any assertion that `.asdlc_worker/scripts/helpers/helper_find_blueprints.sh` is installed, executable, excluded, or tracked.
- [x] 4.2 Grep `tests/` for `helper_find_blueprints` and remove any stale references.
- [x] 4.3 Add a new focused test (location: `tests/ai_skills/yasdef_worker_design_find_blueprints_tests.sh` or pytest equivalent under `tests/skills/`, matching the existing test-file convention in this repo) that:
  - Creates a temporary project dir with `project_stack_blueprint_back.md` and `project_stack_blueprint_front.md`.
  - Creates a feature dir under it with `implementation_plan.md` and `requirements_ears.md`.
  - Writes a synthetic `.asdlc_worker/project_overmind.yaml` with `class: 'back'`.
  - Runs the new Python script from the feature dir.
  - Asserts the output contains "Normalized project class: back", lists the back blueprint under "Relevant blueprint candidates", and lists the front blueprint under "Irrelevant blueprint candidates".

## 5. Validate

- [x] 5.1 Run `tests/ai_scripts/init_asdlc_worker_tests.sh` and confirm pass.
- [x] 5.2 Run the new blueprint-finder test (from task 4.3) and confirm pass.
- [x] 5.3 Run a smoke test in a scratch repo: install via `ai/scripts/init_asdlc_worker.sh`, set up a synthetic project with two blueprints + a feature dir with the required files + a binding file with `class: 'back'`, invoke `uv run python .claude/skills/yasdef-worker-design/scripts/find_blueprints.py` from the feature dir, verify the output names the back blueprint as relevant.
- [x] 5.4 Confirm `ai/scripts/helpers/helper_find_blueprints.sh` is gone from the working tree and from HEAD.
