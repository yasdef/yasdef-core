## Context

`ai/scripts/helpers/helper_find_blueprints.sh` is invoked by exactly one caller in the repository: `ai/skills/yasdef-worker-design/SKILL.md:92`, where the design skill tells the LLM to run it when stack/architecture guidance is needed. The helper resolves the feature directory from `cwd` or `ASDLC_RUNTIME_PLAN_PATH`, reads the `class` scalar from `.asdlc_worker/project_overmind.yaml`, normalizes the class string, and searches the parent project directory for `project_stack_blueprint_*.md` files, filtering by class via path-substring match.

The Python-port migration in `design_docs/orchestrator_to_python_ref_plan.md` removes `.asdlc_worker/scripts/` from target repos entirely: orchestrator and helper logic is consolidated into the globally-installed `yasdef` CLI; per-repo `.asdlc_worker/` becomes data-only. When that lands, the design skill's `.asdlc_worker/scripts/helpers/helper_find_blueprints.sh` invocation breaks — the path no longer exists.

The earlier plan considered porting the helper to a CLI subcommand `yasdef find-blueprints` under `app/blueprint_finder.py` + `cli/find_blueprints.py`. That option was reconsidered and rejected after noting the helper has a single consumer. This CRP locks the alternative: move the logic into the design skill itself, matching the pattern every other skill already uses for its internal scripts.

This CRP is independent of the Python orchestrator port. It can ship first, removing one stale reference before the port begins, and reducing scope of the cutover PR (PR 5 in the Python-port plan).

## Goals / Non-Goals

**Goals:**
- Blueprint discovery for the design skill runs from a Python script inside the design skill bundle, invoked via the same `uv run python .claude/skills/<skill>/scripts/<file>.py` pattern used by sibling scripts (`build_design_context.py`, `check_design_readiness.py`).
- After this CRP, no skill content references `.asdlc_worker/scripts/`.
- The bash helper file is deleted in the same commit set — no deprecation window, single source of truth.

**Non-Goals:**
- Changing the helper's behavior. Feature-dir resolution, class normalization rules, search semantics, and output format stay identical to today's bash.
- Promoting the helper to a `yasdef` CLI subcommand. Single-consumer principle: the helper lives where it is used.
- Generalizing the helper for use by other skills. None need it today; defer until a second consumer appears.
- Changes to the orchestrator scripts or the worker-runtime bootstrap install logic (beyond the natural consequence of deleting the now-unused bash file).
- Editing the Python-port plan doc — separate, applied alongside this CRP but tracked outside its task list.

## Decisions

**Decision 1: Logic ports to a Python script inside the design skill bundle.**

Location: `ai/skills/yasdef-worker-design/scripts/find_blueprints.py`. Same directory as the skill's existing `build_design_context.py` and `check_design_readiness.py`.

Rationale:
- Single consumer. The helper is invoked from one SKILL.md line; promoting to a top-level CLI subcommand creates surface (documentation, testing, versioning) for zero reuse benefit.
- Locality. Every other skill already keeps its internal Python helpers in its own `scripts/` directory.
- Distribution. The skill bundle is shipped as a unit; the helper is part of the contract the skill expects to be available, and shipping them together removes any version-skew concern between skill and helper.
- Reversibility. If a second consumer ever appears (e.g. planning skill needs blueprint lookup), extraction back to a `yasdef <subcommand>` is a mechanical lift — the Python module stays the same, only the invocation surface changes.

**Decision 2: Direct logic port, no behavior changes.**

The Python script preserves:
- Feature-dir resolution: prefer `cwd` if it contains `implementation_plan.md` plus `requirements_ears.md` (or `reqirements_ears.md` — the misspelled fallback in today's bash is kept for compatibility); else fall back to `dirname($ASDLC_RUNTIME_PLAN_PATH)`.
- Binding read: `.asdlc_worker/project_overmind.yaml`, scalar key `class`, single-/double-quoted value handling.
- Class normalization map: `back|backend|api|server → back`; `front|frontend|front-end|web|ui → front`; `mobile|ios|android|react-native → mobile`; anything else → unresolved.
- Search: non-recursive listing of `project_stack_blueprint_*.md` files in the parent of the feature directory; LC_ALL=C sort equivalent (Python's default lexical sort is fine; the bash sort was the default sort under `LC_ALL=C`).
- Class-based filter: case-insensitive substring match on the basename, using the same substring lists as today (`back|backend` for back; `front|frontend|web` for front; `mobile|ios|android` for mobile).
- Output format: the existing human-readable text — `Blueprint helper result` preamble, `Feature folder:`, `Project-level search root:`, `Binding file:`, `Raw project class:`, `Normalized project class:`, `All blueprint candidates:` block, `Relevant blueprint candidates for class <X>:` block, `Irrelevant blueprint candidates for class <X>:` block, final `Relevant blueprint result:` summary line.

Reasons to not "improve" the format or logic during the port:
- Output is consumed by an LLM via narrative in `SKILL.md`. Format changes could require coordinated skill text updates.
- Class normalization is a contract with operators who set `class` in `project_overmind.yaml`. Don't break it.
- Behavioral changes during a port double the risk surface.

**Decision 3: Hardcode `.claude/skills/...` prefix in the SKILL.md invocation.**

The new line at `SKILL.md:92` becomes:

```
uv run python .claude/skills/yasdef-worker-design/scripts/find_blueprints.py
```

Reasons:
- Symmetry with the skill's existing script invocations (`build_design_context.py` and `check_design_readiness.py` are both invoked via the `.claude/skills/...` prefix in this same SKILL.md).
- Skills install at four prefixes (`.claude`, `.codex`, `.github`, `.agents`) per the bootstrap fanout, so the file exists at the `.claude/` path regardless of which runner loaded the SKILL.md.
- Anything more "portable" (e.g. detecting the install prefix dynamically) would diverge from the rest of the skill and add complexity for a non-problem.

**Decision 4: Delete the bash helper in the same change set. No deprecation window.**

Reasons:
- Only one consumer; that consumer updates simultaneously.
- Keeping the bash file around invites stale invocations and confusion about which source of truth wins.
- Matches the `.devin → .agents` rename pattern adopted earlier in this branch: no backward-compat shims for rename / move operations within the orchestrator/skill workspace.

**Decision 5: This CRP is independent of the Python orchestrator port.**

Ships standalone. The Python-port plan (`design_docs/orchestrator_to_python_ref_plan.md`) drops `app/blueprint_finder.py`, `cli/find_blueprints.py`, and the `yasdef find-blueprints` subcommand as a consequence of this CRP, but those edits are documentation, not code, and are applied alongside this CRP without being tasks under it.

## Risks / Trade-offs

- **Script drift between deleted bash and new Python**: the port is mechanical and ~100 lines of awk/grep/find translated to `pathlib`, `re`, and a small YAML scalar reader. Line-by-line review during code review is the mitigation. Adding a small fixture test (synthetic project dir with two matching and two non-matching blueprints; assert the output text matches a golden) is cheap and recommended.
- **Operator debugging workflow change**: operators who today run `bash .asdlc_worker/scripts/helpers/helper_find_blueprints.sh` directly to inspect what the helper finds would invoke `uv run python .claude/skills/yasdef-worker-design/scripts/find_blueprints.py` instead. Accepted — this is a developer-only debug path, not an operator-facing flow.
- **Coupling to `uv` runtime**: the design skill's other scripts already require `uv` to be installed in the runtime environment. Adding one more script that runs the same way doesn't change the coupling.
- **`reqirements_ears.md` typo preservation**: today's bash accepts both the correct `requirements_ears.md` and the typoed `reqirements_ears.md` (`ai/scripts/helpers/helper_find_blueprints.sh:107`). The Python port preserves both for compatibility. Fixing the typo is out of scope for this CRP.

## Migration Plan

1. Author `ai/skills/yasdef-worker-design/scripts/find_blueprints.py`. Port the bash logic line-by-line; preserve output format byte-for-byte where the bash output is single-line text. Code style matches sibling scripts (`build_design_context.py`, `check_design_readiness.py`).
2. Edit `ai/skills/yasdef-worker-design/SKILL.md:92` to invoke `uv run python .claude/skills/yasdef-worker-design/scripts/find_blueprints.py` with no arguments (the script reads cwd / env / binding file the same way the bash did).
3. Delete `ai/scripts/helpers/helper_find_blueprints.sh`.
4. Update `tests/ai_scripts/init_asdlc_worker_tests.sh`: remove any assertion that the helper file exists at install time or is excluded/tracked. Grep for any other test referencing `helper_find_blueprints` and update.
5. Run the existing skill / installer test suite. Add a focused unit fixture for the new Python script (synthetic project dir with two relevant + two irrelevant blueprints; assert the output preamble, both candidate lists, and the final summary line).
6. Smoke test against a scratch repo: set up `.asdlc_worker/project_overmind.yaml` with `class: 'back'`, place `project_stack_blueprint_back.md` and `project_stack_blueprint_front.md` in the parent dir, run the script from the feature dir, verify output names the back blueprint as relevant and the front blueprint as irrelevant.

Rollback: revert the change set. The bash helper file resurrects, SKILL.md line 92 returns to the old invocation, the new Python script and its test are removed.
