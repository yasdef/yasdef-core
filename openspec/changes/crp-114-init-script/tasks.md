## 1. Bootstrap Init Flow

- [ ] 1.1 Create a YASDEF source bootstrap script, for example `ai/scripts/init_asdlc_worker.sh`, that prompts for a target repository path before mutating files.
- [ ] 1.2 Implement target path validation for missing paths, non-directory paths, existing git repository roots, existing directories outside git, and nested non-root git paths.
- [ ] 1.3 Run `git init` in valid target directories that are not already inside a git repository.
- [ ] 1.4 Install first-run runtime files by copying the YASDEF `ai/` runtime into `<target-repo>/.asdlc_worker/`.
- [ ] 1.5 On first install, write `.asdlc_worker/asdlc_worker.yaml` with the resolved worker repository root.
- [ ] 1.6 Add generated runtime paths to `<target-repo>/.git/info/exclude` idempotently.
- [ ] 1.7 Rename the copied runtime worker-binding script from `init_worker.sh` to `register_worker.sh`.

## 2. Update Mode

- [ ] 2.1 Detect an existing `<target-repo>/.asdlc_worker/` directory and switch init into update mode.
- [ ] 2.2 Overwrite only generated runtime paths: `scripts`, `scripts/helpers`, `golden_examples`, `setup`, `templates`, `logs`, `prompts`, and `AI_DEVELOPMENT_PROCESS.md`.
- [ ] 2.3 Preserve all non-generated files and directories under `.asdlc_worker/`, including `asdlc_worker.yaml`, local binding, feature sync, decisions, history, and in-flight artifacts.
- [ ] 2.4 Make repeated init/update runs deterministic and safe when exclude entries already exist.

## 3. Runtime Path Resolution

- [ ] 3.1 Add a shared shell helper that validates `.asdlc_worker` layout and resolves `ASDLC_WORKER_HOME` plus `WORKER_REPO_ROOT`.
- [ ] 3.2 Refactor `orchestrator.sh` to use `.asdlc_worker` for runtime state and the parent target repo for git, branches, and source edits.
- [ ] 3.3 Refactor `register_worker.sh` to use `.asdlc_worker` for binding state and the parent target repo for git/project checks.
- [ ] 3.4 Refactor `ai_design.sh`, `ai_plan.sh`, `ai_implementation.sh`, `ai_user_review.sh`, `ai_audit.sh`, and `post_review.sh` to use the shared runtime/root resolution.
- [ ] 3.5 Refactor copied helper scripts under `.asdlc_worker/scripts/helpers/` to use `.asdlc_worker` runtime paths and target repo root paths consistently.
- [ ] 3.6 Add fail-fast unsupported-layout checks so copied runtime scripts no longer run from the YASDEF source checkout or a root `ai/` layout.

## 4. Binding And Runtime Artifacts

- [ ] 4.1 Move durable worker/project binding reads and writes from root `ai/project_overmind.yaml` to `.asdlc_worker/project_overmind.yaml`.
- [ ] 4.2 Move feature sync, prompts, logs, decisions, open questions, blocker log, user review, history, designs, step plans, and review results under `.asdlc_worker/`.
- [ ] 4.3 Move worker runtime copies of coordinator artifacts to `.asdlc_worker/overmind/implementation_plan.md` and `.asdlc_worker/overmind/reqirements_ears.md`.
- [ ] 4.4 Keep source-of-truth ASDLC feature artifacts in the bound project repo and mirror them into `.asdlc_worker/overmind/` before phase execution.

## 5. Tests

- [ ] 5.1 Add `init_asdlc_worker` tests for missing target path, non-directory target, nested non-root git path, existing git root, and no-git target with `git init`.
- [ ] 5.2 Add install/update tests for `.asdlc_worker` copy scope, overwrite scope, preserved non-generated files, and idempotent `.git/info/exclude` entries.
- [ ] 5.3 Rename or replace `init_worker` tests with `register_worker` tests for registered-worker binding behavior.
- [ ] 5.4 Update orchestrator assignment/resume/debug tests to use `.asdlc_worker` runtime paths and target repo root source paths.
- [ ] 5.5 Update phase prompt/helper tests that assert root `ai/` paths.
- [ ] 5.6 Add unsupported-layout tests proving scripts fail when run from YASDEF source layout or root `ai/` runtime layout.
- [ ] 5.7 Run the affected `tests/ai_scripts/` suites from the repository root.
