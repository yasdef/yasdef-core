## Context

`ai/scripts/init_worker.sh` is currently designed as a combined onboarding and shared-state mutation tool: it generates or reuses a worker UUID, switches branches, updates `overmind/worker_registry.yaml`, pushes remote changes, and persists a local `ai/<uuid>_dont_touch.txt` file. That implementation no longer matches the intended workflow. Worker registration is moving to the overmind side first, and the worker-side init flow should only validate an existing registration and bind the local worker repo to it.

This change is constrained by two existing repo contracts. First, worker-local artifacts belong under `ai/`. Second, the new overmind registration flow being introduced for project-level onboarding stores worker entries in project-scoped `workers.yaml` files rather than having the worker repo generate its own identity. The worker-side script therefore needs to read registration data from an operator-provided overmind repo path, not create that data itself.

## Goals / Non-Goals

**Goals:**
- Replace UUID generation/discovery with an interactive prompt for a user-provided worker UUID.
- Prompt for an overmind repo path and validate that it contains usable project worker registry data.
- Resolve exactly one matching registered worker entry from the provided overmind repo and reuse its `class` and `status`.
- Create a single local binding artifact at `ai/project_overmind.yaml` containing the overmind source path, worker UUID, class, and current status.
- Remove worker-init behavior that mutates shared overmind state, creates legacy `*_dont_touch.txt` identity files, or pushes remote changes.
- Keep the broader ownership split unchanged: shared worker registration remains on the overmind side, local binding remains in the worker repo.

**Non-Goals:**
- Change the overmind-side worker registration format beyond consuming its existing `workers.yaml` records.
- Add worker registration, worker deletion, or worker-status editing to `ai/scripts/init_worker.sh`.
- Support multiple overmind repos or multiple simultaneous worker bindings in one local repo.
- Introduce new CLI flags or non-interactive modes.

## Decisions

1. Persist the local binding artifact as `ai/project_overmind.yaml`.
Rationale: worker-local onboarding artifacts already live under `ai/`, so keeping the new binding file there preserves repo structure and avoids introducing a second local coordination folder.
Alternative considered: write `project_overmind.yaml` at repository root. Rejected because it mixes worker-local process state with repo-level project files.

2. Treat the provided overmind path as a repo root to scan for project-scoped `workers.yaml` files.
Rationale: the worker-side flow asks only for an overmind repo path, not a specific project path. Scanning the repo for project worker registries bridges that UX with the new project-level registration model.
Alternative considered: require a direct path to one `workers.yaml` file. Rejected because it changes the requested UX and forces the operator to know internal project file locations.

3. Resolve the worker registration by requiring exactly one matching UUID across discovered `workers.yaml` files.
Rationale: a local binding must point to one unambiguous overmind registration record. Silent first-match behavior would risk binding a developer repo to the wrong project worker entry.
Alternative considered: accept the first match found during recursive scan. Rejected because duplicate UUID presence should be surfaced as a data integrity problem, not hidden.

4. Reuse the registered worker `class` and `status` directly in `ai/project_overmind.yaml`.
Rationale: the overmind-side worker registry is the source of truth for worker metadata. The local binding file should mirror the validated registration instead of recomputing or renaming fields.
Alternative considered: persist only the UUID and overmind path locally. Rejected because the user explicitly asked for class and current status in the local file.

5. Stop all shared-state mutation from `ai/scripts/init_worker.sh`.
Rationale: the worker-side script should no longer generate UUIDs, update shared registries, create branch-local commits, or push to remotes. Those responsibilities now belong to overmind-side registration.
Alternative considered: keep backward-compatible auto-registration as a fallback. Rejected because it would preserve two conflicting onboarding paths and undermine the new separation of responsibilities.

6. Use fail-fast validation with actionable messages for missing overmind path, missing registry files, unresolved UUID, and duplicate UUID matches.
Rationale: the operator needs immediate clarity about whether the problem is the path, the overmind repo contents, or the registration state for the supplied UUID.
Alternative considered: generic “worker not found” failures. Rejected because they obscure which prerequisite is actually broken.

## Risks / Trade-offs

- [Risk] The user request says “contains `workers.sh`”, while the new overmind worker-registration contract is file-backed `workers.yaml`. -> Mitigation: standardize this change on scanning project `workers.yaml` files and document that assumption in the change artifacts.
- [Risk] Recursive repo scanning can find more than one matching UUID if upstream registration data becomes inconsistent. -> Mitigation: fail fast on duplicate matches and require operators to fix the overmind data before binding locally.
- [Risk] Removing legacy `ai/<uuid>_dont_touch.txt` behavior is a breaking change for existing worker-init expectations. -> Mitigation: update specs, tests, and docs together and make the new `ai/project_overmind.yaml` artifact explicit.
- [Risk] The worker repo may no longer need branch switching or remote validation, which can make older tests and docs misleading. -> Mitigation: rewrite `init_worker` coverage around local binding behavior and remove assertions tied to overmind branch mutation.

## Migration Plan

1. Replace the current `ai/scripts/init_worker.sh` flow with interactive UUID/path prompts, overmind repo scanning, UUID lookup, and local `ai/project_overmind.yaml` writes.
2. Remove helpers related to UUID generation, overmind registry mutation, branch switching, committing, and pushing.
3. Update `tests/ai_scripts/init_worker_tests.sh` to cover prompt-driven success, missing path, missing registries, unresolved UUID, duplicate UUID match handling, and deterministic local file content.
4. Update worker-init documentation so it describes overmind-first worker registration and local project binding rather than automatic registration.
5. Confirm `openspec status --change crp-105-worker-init-overmind-project-binding` is apply-ready after tasks are created.

Rollback strategy: restore the previous generated-ID and shared-registry mutation flow in `ai/scripts/init_worker.sh`, along with the legacy test suite and documentation, while leaving any already-created `ai/project_overmind.yaml` files for manual cleanup.

## Open Questions

- None. The main implementation assumption is that the worker-side lookup targets project `workers.yaml` files created by the overmind-side registration flow.
