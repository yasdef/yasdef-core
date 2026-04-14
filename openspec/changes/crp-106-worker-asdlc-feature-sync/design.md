## Context

Worker execution is moving from one branch-scoped coordinator plan to feature-scoped ASDLC project artifacts under `projects/<project-id>/<feature-id>/`, but the current worker runtime still assumes a single local `overmind/implementation_plan.md`, a single local `overmind/reqirements_ears.md`, and worker identity derived from `ai/*_dont_touch.txt`.

That leaves three gaps:

1. The worker repo is bound only to an overmind source path and worker UUID, not to one project.
2. The orchestrator has no explicit rule for selecting one feature when the same worker has assignments in multiple features.
3. Existing phase scripts still expect stable local runtime paths, so we need a compatibility layer instead of forcing every phase script to read ASDLC feature paths directly.

This change is constrained by existing repo rules:

- Keep worker-local process state under `ai/`.
- Keep worker phase scripts operating on local `overmind/` runtime paths.
- Avoid new CLI flags unless explicitly required.
- Keep shell-based implementation and test coverage under `tests/ai_scripts/`.

## Goals / Non-Goals

**Goals:**
- Extend worker binding so one local repo is durably bound to one ASDLC project and one worker UUID.
- Make orchestrator select exactly one active feature per run with no hidden prioritization.
- Preserve existing worker phase contracts by mirroring selected feature artifacts into local `overmind/` on branch `overmind`.
- Record local feature-sync metadata separately from project binding for traceability and `--resume` continuity.
- Sync worker-owned `implementation_plan.md` updates back to the selected ASDLC feature artifact.

**Non-Goals:**
- Redesign ASDLC feature artifact schemas beyond the binding and sync metadata needed for worker orchestration.
- Add new non-interactive selection flags or heuristic feature-priority rules.
- Make phase scripts read ASDLC feature folders directly instead of local runtime mirrors.
- Rename the worker runtime EARS path away from legacy `overmind/reqirements_ears.md` in this change.

## Decisions

1. Extend `ai/project_overmind.yaml` to bind a repo to one ASDLC project, not just a source repo.
Rationale: feature discovery has to be scoped to one project before feature selection begins. Persisting `project_id` alongside `overmind_source_path`, `worker_uuid`, `class`, and `status` makes that binding durable and avoids rescanning the entire source tree for every orchestrator run.
Alternative considered: derive the bound project dynamically from `workers.yaml` on each orchestrator run. Rejected because it keeps project binding implicit, makes errors less actionable, and weakens reproducibility.

2. Keep current-feature state in a separate local file `ai/feature_sync.yaml`.
Rationale: project binding is durable onboarding state, while selected feature state is per-run runtime context. Splitting them prevents stale feature context from mutating the onboarding contract and makes resume logic easier to validate.
Alternative considered: store current feature fields directly in `ai/project_overmind.yaml`. Rejected because it mixes durable binding with transient run state and makes rebind versus resume semantics ambiguous.

3. Use an explicit candidate-selection rule with interactive disambiguation.
Rationale: orchestrator should only auto-select when there is exactly one eligible feature. If multiple features are eligible, prompting the user is the only reliable behavior that does not invent hidden priority logic. For `--resume <step>`, valid `ai/feature_sync.yaml` state should be reused first so in-progress work does not re-prompt.
Alternative considered: silently pick the first feature by lexical order, modification time, or first discovered assigned step. Rejected because those orders are incidental and can route work to the wrong feature.

4. Preserve the worker runtime contract by mirroring the selected feature into local `overmind/` paths on branch `overmind`.
Rationale: `ai_design.sh`, `ai_plan.sh`, `ai_audit.sh`, readiness helpers, and tests already target `overmind/implementation_plan.md` and `overmind/reqirements_ears.md`, and the current workflow starts worker orchestration from branch `overmind`. Mirroring selected feature artifacts onto that branch keeps the runtime contract and branch model aligned while changing only orchestration and sync logic.
Alternative considered: rewrite every phase script to consume source feature paths directly. Rejected because it broadens the change significantly and increases regression surface.

5. Keep source and runtime EARS paths intentionally asymmetric for compatibility.
Rationale: ASDLC feature folders should use correctly spelled `requirements_ears.md`, while worker runtime continues to use legacy `overmind/reqirements_ears.md` until a dedicated rename change is made. This isolates compatibility handling to orchestrator sync instead of forcing a repo-wide rename here.
Alternative considered: rename the worker runtime file to `overmind/requirements_ears.md` immediately. Rejected because many scripts, docs, and tests still use the legacy path.

6. Sync back only the worker-owned runtime plan copy, and do it at phase boundaries after mutations.
Rationale: the local mirrored `overmind/implementation_plan.md` is a runtime working copy. When planning, ai_audit, or post_review changes it, orchestrator should write the updated content back to the selected feature's source plan before advancing. This keeps the selected feature artifact authoritative without requiring every phase script to know the source path.
Alternative considered: defer all sync-back to the end of the entire run. Rejected because a failed later phase could leave source and runtime plans diverged for too long.

## Risks / Trade-offs

- [Risk] `ai/project_overmind.yaml` schema changes are breaking for existing worker-init behavior. -> Mitigation: update worker-init, orchestrator validation, tests, and README together, and fail fast on missing `project_id`.
- [Risk] Legacy runtime path `overmind/reqirements_ears.md` differs from source feature path `requirements_ears.md`. -> Mitigation: make the mapping explicit in specs, tests, and orchestrator sync helpers.
- [Risk] Stale `ai/feature_sync.yaml` could point to a deleted or reassigned feature. -> Mitigation: validate metadata on each `--resume <step>` and discard/recompute when the feature or assigned step is no longer valid.
- [Risk] Sync-back may overwrite coordinator changes if the selected source plan changed independently while the worker was running. -> Mitigation: keep sync-back scoped to the currently selected feature and fail fast on missing or invalid targets; coordinator-side conflict strategy remains out of scope for this change.
- [Risk] Prompting when multiple features are eligible introduces interactive blocking. -> Mitigation: limit prompting to true ambiguity and reuse valid feature-sync metadata during normal resume flows.

## Migration Plan

1. Extend `ai/scripts/init_worker.sh` to persist `project_id` in `ai/project_overmind.yaml` together with existing worker metadata.
2. Add orchestrator helpers that validate project binding, establish local branch `overmind`, scan `projects/<project-id>/<feature-id>/`, resolve candidate features, prompt only when multiple candidates remain, and mirror the selected feature into local `overmind/` on that branch.
3. Add `ai/feature_sync.yaml` writing and validation for traceability and resume reuse.
4. Update design-gate and post-phase sync logic so local `overmind/implementation_plan.md` changes are copied back to the selected feature source plan.
5. Update shell tests and README guidance for binding, multi-feature selection, mirroring, resume reuse, and fail-fast EARS handling.

Rollback strategy: restore orchestrator discovery from local `overmind/implementation_plan.md` plus legacy worker identity behavior, remove `ai/feature_sync.yaml` handling, and revert `ai/project_overmind.yaml` to the previous field set while cleaning up any partially created feature-sync metadata manually.

## Open Questions

- None. The feature-selection rule is explicit: `0` candidates fails, `1` auto-selects, and `>1` asks the user unless valid resume metadata already disambiguates the in-progress step.
