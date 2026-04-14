## 1. Extend worker project binding

- [x] 1.1 Update `ai/scripts/init_worker.sh` to resolve the worker's bound ASDLC project from project-scoped `workers.yaml` files and persist `project_id` in `ai/project_overmind.yaml`.
- [x] 1.2 Keep `ai/project_overmind.yaml` deterministic while preserving existing worker metadata fields and excluding transient current-feature state.
- [x] 1.3 Add or update `tests/ai_scripts/init_worker_tests.sh` coverage for project-scoped binding success, ambiguous multi-project matches, and deterministic rewritten binding content.

## 2. Implement orchestrator feature discovery and runtime mirroring

- [x] 2.1 Refactor `ai/scripts/orchestrator.sh` to read worker identity and project binding from `ai/project_overmind.yaml` instead of `ai/*_dont_touch.txt`.
- [x] 2.2 Add bound-project feature scanning that builds the candidate feature set from feature `implementation_plan.md` files containing worker-assigned work, including requested-step filtering for `--step` and `--resume`.
- [x] 2.3 Implement the explicit selection rule in orchestrator: fail on zero candidate features, auto-select one candidate feature, and prompt the user when multiple candidate features remain.
- [x] 2.4 Mirror the selected feature's `implementation_plan.md` into `overmind/implementation_plan.md` and `requirements_ears.md` into legacy worker runtime path `overmind/reqirements_ears.md` on branch `overmind`, with fail-fast handling for missing or unusable EARS input.
- [x] 2.5 Write local `ai/feature_sync.yaml` metadata on branch `overmind` with selected project/feature identity, source paths, runtime mirror paths, branch context, selection mode, and step context for traceability.

## 3. Integrate resume continuity and sync-back behavior

- [x] 3.1 Reuse valid `ai/feature_sync.yaml` on `--resume <step>` so in-progress runs keep the same selected feature without re-prompting.
- [x] 3.2 Detect stale or invalid feature-sync metadata and recompute candidate features instead of trusting stale local state.
- [x] 3.3 Update orchestrator phase-boundary logic so worker-owned changes to local `overmind/implementation_plan.md` on branch `overmind` are synced back to the selected feature source plan after planning, ai_audit, and post_review mutations.
- [x] 3.4 Ensure design entry is blocked when selected-feature `requirements_ears.md` cannot be mirrored into local runtime paths.

## 4. Cover routing changes with tests and docs

- [x] 4.1 Expand `tests/ai_scripts/orchestrator_assignment_tests.sh` for bound-project feature scanning, single-feature auto-selection, and multi-feature user prompt behavior.
- [x] 4.2 Expand `tests/ai_scripts/orchestrator_resume_tests.sh` for valid feature-sync reuse and stale feature-sync invalidation on resume.
- [x] 4.3 Add or update shell coverage for branch-`overmind` feature mirroring, missing selected-feature EARS failures, and `implementation_plan.md` sync-back to the selected feature source path.
- [x] 4.4 Update `Readme.md` and any orchestrator-facing docs to describe project binding, selected-feature mirroring, `ai/feature_sync.yaml`, and the explicit multi-feature selection rule.
- [x] 4.5 Run the relevant `tests/ai_scripts/` suites from repository root and confirm `openspec status --change crp-106-worker-asdlc-feature-sync` reports the change as apply-ready.
