## 1. Refactor `init_worker.sh` for single-project source

- [x] 1.1 Update prompt copy and inline help in `ai/scripts/init_worker.sh` so the operator-provided path is documented as a single ASDLC project repo (not a parent of many projects).
- [x] 1.2 Remove `discover_workers_files()` recursive scan; replace with a check that `<overmind_source_path>/workers.yaml` exists as a regular file. Fail fast with an explicit error when it is missing.
- [x] 1.3 Remove `derive_project_id_from_workers_file()`; add a helper that reads `meta_info.project_id` from `<overmind_source_path>/init_progress_definition.yaml`. Fail fast when the file is missing, when `meta_info:` is absent, or when `project_id` is missing/empty.
- [x] 1.4 Simplify `parse_registry_matches_from_file` call site to operate on the single root `workers.yaml`. Keep current uniqueness check inside that file: 0 matches → fail, >1 matches inside the same file → fail with a clear duplicate-UUID error.
- [x] 1.5 Update `write_project_binding_file()` to keep field names unchanged but write `overmind_source_path` as the single project repo path and `project_id` as the value read from `init_progress_definition.yaml`.
- [x] 1.6 Update final stdout summary so logs reflect the new semantics (e.g., `Project repo path:` line) without renaming fields in the binding file itself.

## 2. Refactor `orchestrator.sh` project resolution

- [x] 2.1 In `load_project_binding()`, set `BOUND_PROJECT_PATH="$BINDING_OVERMIND_SOURCE_PATH"`. Remove the `<source>/projects/<id>` and `<source>/<id>` fallback branches.
- [x] 2.2 Add a sanity check after `BOUND_PROJECT_PATH` is set: read `meta_info.project_id` from `<BOUND_PROJECT_PATH>/init_progress_definition.yaml` and fail fast when the file is missing or when its `project_id` does not match `BINDING_PROJECT_ID`.
- [x] 2.3 Update feature enumeration in `ensure_feature_runtime_context()` so the `find` over `BOUND_FEATURES_ROOT` skips `.git` and any subdirectory without an `implementation_plan.md` file.
- [x] 2.4 Update the default-mode log line at the orchestrator startup banner to reference `<project-repo>/<feature-id>/implementation_plan.md` and `<project-repo>/<feature-id>/requirements_ears.md` (drop the `projects/<project-id>/` segment).
- [x] 2.5 Confirm `--standalone` code path is unchanged and still uses local `overmind/` runtime files without touching the new project-repo resolution code.
- [x] 2.6 Update operator-facing fail-fast messages in `load_project_binding()` to reference the single-project semantics ("bound overmind project repo" instead of "bound project path under overmind source").

## 3. Update README and operator docs

- [x] 3.1 Update `Readme.md` step `4` so the prompt description states the path points to a single ASDLC project repo (not a multi-project parent). Mention that `init_worker.sh` reads `project_id` from `<project_repo>/init_progress_definition.yaml`.
- [x] 3.2 Update `Readme.md` step `5` (and the **Main process artifacts** section) so source-of-truth paths are written as `<project-repo>/<feature-id>/implementation_plan.md` and `<project-repo>/<feature-id>/requirements_ears.md` (no `projects/<project-id>/` segment).
- [x] 3.3 Update `Readme.md` step `7` candidate-discovery bullet so it reads "orchestrator scans bound project repo features (`<project-repo>/<feature-id>/implementation_plan.md`)" and notes that `.git` is skipped.
- [x] 3.4 Update `Readme.md` step `5.1` (standalone) only where path examples are shown; do not change standalone behavior text.

## 4. Update fixtures and tests

- [x] 4.1 Update `tests/ai_scripts/init_worker_tests.sh` fixtures: place `workers.yaml` at the root of the simulated project repo, add `init_progress_definition.yaml` with `meta_info.project_id`, remove the `projects/<id>/` directory.
- [x] 4.2 Update `tests/ai_scripts/init_worker_tests.sh` test cases: cover happy path (root `workers.yaml` + valid `init_progress_definition.yaml`), missing `workers.yaml`, missing `init_progress_definition.yaml`, missing `meta_info.project_id`, duplicate UUIDs in the single `workers.yaml`.
- [x] 4.3 Update `tests/ai_scripts/orchestrator_assignment_tests.sh` fixtures and assertions: remove `projects/<id>/` wrapper; cover `BOUND_PROJECT_PATH == overmind_source_path` resolution; add coverage for `.git` and non-feature subdirectories being skipped during feature enumeration.
- [x] 4.4 Update `tests/ai_scripts/orchestrator_resume_tests.sh` and `tests/ai_scripts/orchestrator_debug_tests.sh` fixtures to the new single-project layout where they touch project paths.
- [x] 4.5 Update `tests/ai_scripts/crp-068/feature_path_override_contract_tests.sh` fixture (`asdlc/projects/p1/init_progress_definition.yaml` → `asdlc/init_progress_definition.yaml` plus root `workers.yaml`) without changing the contract being tested.
- [x] 4.6 Add a focused test verifying that orchestrator fails fast when `<project_repo>/init_progress_definition.yaml` is missing or when its `meta_info.project_id` does not match the bound `project_id`.
- [x] 4.7 Run all `tests/ai_scripts/` suites from the repository root and confirm green status; verify `openspec status --change crp-110-single-project-overmind-source` reports apply-ready.
