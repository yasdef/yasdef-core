## Why

Overmind has changed: there is no longer a centralized overmind folder that hosts many projects under `projects/<project-id>/`. Each ASDLC project now lives in its own repo, and operators point worker tooling directly at that single project repo. The current `init_worker.sh` and `orchestrator.sh` resolve project paths under a multi-project parent (`<source>/projects/<id>/` or `<source>/<id>/`), which is wrong against the new layout and causes worker binding and feature discovery to fail or resolve to non-existent paths.

## What Changes

- Treat `overmind_source_path` (in `ai/project_overmind.yaml`) as the path to a single ASDLC project repo. Field name and binding filename are unchanged; only the semantics change.
- `ai/scripts/init_worker.sh`:
  - Expect exactly one `workers.yaml` at `<project_repo>/workers.yaml`. Remove recursive `find` for `workers.yaml` and the multi-project disambiguation logic.
  - Read `project_id` from `<project_repo>/init_progress_definition.yaml` under `meta_info.project_id` instead of deriving it from path components (`projects/<id>/` or `<id>/`).
  - Fail fast when `<project_repo>/workers.yaml` is missing, when `<project_repo>/init_progress_definition.yaml` is missing, or when `meta_info.project_id` is absent/empty.
  - Validate the operator-provided UUID resolves to exactly one entry in that single `workers.yaml`.
- `ai/scripts/orchestrator.sh`:
  - Set `BOUND_PROJECT_PATH = BINDING_OVERMIND_SOURCE_PATH` directly. Remove `<source>/projects/<id>` and `<source>/<id>` fallback resolution.
  - Validate that `<project_repo>/init_progress_definition.yaml` exists and that its `meta_info.project_id` matches the bound `project_id` in `ai/project_overmind.yaml`. Mismatch fails fast.
  - When enumerating feature subdirectories, skip `.git` and any subdirectory that does not contain `implementation_plan.md`.
  - Update default-mode startup log to reference `<project-repo>/<feature-id>/implementation_plan.md` instead of `projects/<project-id>/<feature-id>/implementation_plan.md`.
- `--standalone` mode is unchanged. It continues to skip ASDLC discovery/validation and use local `overmind/` runtime files only.
- `Readme.md`:
  - Update step `4` (init_worker) to clarify the path points to a single ASDLC project repo (not a parent of many projects).
  - Update step `5` and the **Main process artifacts** section so source artifact paths read `<project-repo>/<feature-id>/implementation_plan.md` and `<project-repo>/<feature-id>/requirements_ears.md`.
  - Update step `7` candidate-discovery wording: orchestrator scans feature subdirectories of the bound project repo, skipping `.git`.
- Tests under `tests/ai_scripts/`:
  - Rebuild fixtures so the project repo root contains `workers.yaml` and `init_progress_definition.yaml`, with feature subdirectories at the root. Remove the `projects/<id>/` wrapper from fixture trees.
- **BREAKING**: existing workers must re-run `ai/scripts/init_worker.sh` against the new single-project repo path. The previous multi-project source layout is no longer supported. No backward-compatibility shim.

## Capabilities

### Modified Capabilities

- `worker-overmind-registration`: source layout is a single ASDLC project repo with one `workers.yaml` at the repo root; `project_id` is read from `<project_repo>/init_progress_definition.yaml` `meta_info.project_id` instead of being derived from path segments.
- `orchestrator-worker-assigned-step-routing`: the bound project path equals `overmind_source_path` directly, with no `projects/<id>/` or `<id>/` fallback resolution; feature enumeration skips `.git` and any subdir without `implementation_plan.md`.
- `overmind-process-artifact-ownership`: source artifact paths use `<project-repo>/<feature-id>/implementation_plan.md` and `<project-repo>/<feature-id>/requirements_ears.md` (no `projects/` wrapper).

## Impact

- Affected code:
  - `ai/scripts/init_worker.sh`
  - `ai/scripts/orchestrator.sh`
- Affected docs:
  - `Readme.md` (steps 4, 5, 7, 5.1 wording where relevant; **Main process artifacts** section)
- Affected tests:
  - `tests/ai_scripts/init_worker_tests.sh`
  - `tests/ai_scripts/orchestrator_assignment_tests.sh`
  - `tests/ai_scripts/orchestrator_resume_tests.sh`
  - `tests/ai_scripts/orchestrator_debug_tests.sh`
  - `tests/ai_scripts/crp-068/feature_path_override_contract_tests.sh` (fixture only — no contract change here)
- Affected operator flows:
  - One-time re-run of `init_worker.sh` against the new project repo path is required for every worker.
  - Default orchestrator runs after re-binding read source artifacts directly from `<project_repo>/<feature-id>/`.
- Out of scope:
  - No changes to capability names, skills under `.codex/skills/overmind-*`, or the `overmind` term in user-facing docs.
  - No changes to `--standalone` behavior.
  - No rename of `ai/project_overmind.yaml`, `overmind_source_path` field, or any field in `ai/feature_sync.yaml`.
