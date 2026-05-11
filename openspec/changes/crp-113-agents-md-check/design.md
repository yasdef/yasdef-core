## Context

`ai/scripts/init_worker.sh` already resolves the local git repo root, the bound ASDLC project repo path, the project ID, and the registered worker metadata before it calls `checkout_or_create_overmind_branch`. That point is the last moment where the script is still on the operator's current branch while also knowing the worker class needed to select a class-specific project blueprint.

The check is advisory. Missing `AGENTS.md` should not block binding, because init still needs to support repositories that are being prepared for the first time.

## Goals / Non-Goals

**Goals:**

- Warn operators when the local worker repo root lacks `AGENTS.md`.
- Include the class-specific blueprint path in the warning when `<project_repo>/project_stack_blueprint_<class>.md` exists.
- Run the check after worker class resolution and before switching to `overmind`.
- Keep the flow non-blocking and deterministic.

**Non-Goals:**

- Do not create or modify `AGENTS.md`.
- Do not validate `AGENTS.md` content.
- Do not add CLI flags, prompts, or branch behavior changes.
- Do not fail init when the guidance file or blueprint is absent.

## Decisions

- Add a small helper, for example `warn_missing_agents_guidance`, and call it immediately before `checkout_or_create_overmind_branch`.
  - Rationale: this keeps the check in the current branch and after `WORKER_CLASS` is populated.
  - Alternative considered: checking before registry parsing. That cannot choose the class-specific blueprint.

- Define the local worker repo root as `REPO_ROOT`, which is the git top-level and equivalent to the directory one level above the repo-local `ai/` folder for this script layout.
  - Rationale: `resolve_repo_root` already centralizes this path and the script writes `ai/project_overmind.yaml` relative to it.
  - Alternative considered: deriving `dirname "$REPO_ROOT/ai"`. That adds no value and is less direct.

- Resolve the blueprint path as `$OVERMIND_SOURCE_PATH/project_stack_blueprint_${WORKER_CLASS}.md`.
  - Rationale: `OVERMIND_SOURCE_PATH` is already the single ASDLC project repo root containing `init_progress_definition.yaml`.
  - Alternative considered: searching for any matching blueprint. The requirement names the exact project-level class-specific file.

- Print warnings to standard output.
  - Rationale: existing success reporting uses standard output and tests already assert combined script output.
  - Alternative considered: standard error. That would make the warning feel like a failure even though the check is advisory.

## Risks / Trade-offs

- Class values containing unexpected path characters could point outside the project repo if used directly in a path. Mitigation: treat the class as existing registry metadata and add tests for normal backend/frontend/mobile class values; if stronger validation becomes necessary, handle it as a separate requirement.
- The exact warning text is operator-facing and may be brittle in tests. Mitigation: assert the stable core phrase and blueprint path where appropriate.
- Repositories with `AGENTS.md` generated later will still bind successfully. This is intentional because the warning is non-blocking.
