## 1. Replace init-worker onboarding flow

- [x] 1.1 Refactor `ai/scripts/init_worker.sh` to remove UUID generation/discovery, shared overmind registry mutation, commit/push logic, and legacy `ai/*_dont_touch.txt` handling.
- [x] 1.2 Add interactive prompts for worker UUID and overmind repo path, with fail-fast validation for missing path, unusable overmind worker registry data, unresolved UUID, and duplicate UUID matches.
- [x] 1.3 Scan the provided overmind repo for project `workers.yaml` files, resolve exactly one matching worker entry, and extract its `class` and `status`.
- [x] 1.4 Write `ai/project_overmind.yaml` deterministically with overmind source path, worker UUID, class, and status while preserving the starting branch.

## 2. Update worker-init coverage and docs

- [x] 2.1 Rewrite `tests/ai_scripts/init_worker_tests.sh` around prompt-driven local binding behavior instead of remote registration, branch switching, and worker-id file commits.
- [x] 2.2 Add test coverage for missing overmind path, missing `workers.yaml`, unknown UUID, duplicate UUID match, deterministic re-run behavior, and absence of legacy `ai/*_dont_touch.txt` artifacts.
- [x] 2.3 Update worker-init documentation to describe overmind-first worker registration and local `ai/project_overmind.yaml` binding.

## 3. Validate OpenSpec readiness

- [x] 3.1 Run the relevant `tests/ai_scripts/` worker-init suite from repository root after implementation.
- [x] 3.2 Run `openspec status --change crp-105-worker-init-overmind-project-binding` and confirm the change remains apply-ready.
