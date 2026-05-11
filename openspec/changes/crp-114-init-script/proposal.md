## Why

Workers should no longer execute YASDEF scripts from the YASDEF repository checkout or require users to manually copy `ai/` into a target project. The worker tooling needs an explicit init flow that installs and updates a repo-local `.asdlc_worker/` runtime in the target repo root, so all scripts run from the actual worker repository context.

## What Changes

- Add a YASDEF source bootstrap script, `ai/scripts/init_asdlc_worker.sh`, that prompts the operator for a target repository path instead of assuming the current YASDEF repo is the runtime repo.
- Rename the copied runtime worker-binding script from `init_worker.sh` to `register_worker.sh` so installation/update and worker registration are separate commands.
- Validate the target path before any mutation:
  - fail fast when the path does not exist,
  - fail fast when the path is not a directory,
  - allow targets with no git repository and initialize them with `git init`,
  - allow targets that are the git repository root,
  - fail fast when the target is inside a git repository but is not that repository root.
- Install the worker runtime under `<target-repo>/.asdlc_worker/` by copying the current YASDEF `ai/` runtime content into that directory.
- Persist the target repository root in `<target-repo>/.asdlc_worker/asdlc_worker.yaml` as the canonical worker repo root binding.
- Change script runtime assumptions so worker scripts are only supported when running from the target repo with scripts located one level below root in `.asdlc_worker/`; running scripts directly from the YASDEF source checkout is no longer supported.
- Update `orchestrator.sh`, phase scripts, and helpers so they derive:
  - runtime home as `<target-repo>/.asdlc_worker`,
  - worker repo root as the parent of `.asdlc_worker`,
  - process/templates/prompts/log paths from `.asdlc_worker/...`,
  - project code, git operations, branch operations, and source changes from `<target-repo>/...`.
- Ensure scripts fail fast with a meaningful message when executed from an unsupported layout, such as the YASDEF source repo or any location where the script directory is not under `<repo-root>/.asdlc_worker/scripts`.
- Add the generated runtime-only folders and files to `<target-repo>/.git/info/exclude`:
  - `.asdlc_worker/scripts`
  - `.asdlc_worker/scripts/helpers`
  - `.asdlc_worker/golden_examples`
  - `.asdlc_worker/setup`
  - `.asdlc_worker/templates`
  - `.asdlc_worker/logs`
  - `.asdlc_worker/prompts`
  - `.asdlc_worker/AI_DEVELOPMENT_PROCESS.md`
- Treat an existing `<target-repo>/.asdlc_worker/` directory as update mode:
  - overwrite `.asdlc_worker/scripts`, `.asdlc_worker/scripts/helpers`, `.asdlc_worker/golden_examples`, `.asdlc_worker/setup`, `.asdlc_worker/templates`, `.asdlc_worker/logs`, `.asdlc_worker/prompts`, and `.asdlc_worker/AI_DEVELOPMENT_PROCESS.md`,
  - preserve all other files under `.asdlc_worker/`, including local binding/state files such as `asdlc_worker.yaml` unless the proposal/spec phase explicitly identifies them as generated update targets.
- Update tests to cover the init/update flow as the only supported worker runtime installation path.
- **BREAKING**: running worker scripts directly from the YASDEF repository or from a manually copied root `ai/` folder is no longer supported.

## Capabilities

### New Capabilities

- `worker-runtime-bootstrap`: Defines initialization and update behavior for installing YASDEF worker runtime files into a target repo-local `.asdlc_worker/` directory, including target repo validation, `git init`, generated-file exclusion, and preservation of local worker state.

### Modified Capabilities

- `worker-overmind-registration`: Worker registration requirements change from `init_worker.sh` binding an already-copied `ai/` folder to `register_worker.sh` binding an already-bootstrapped `.asdlc_worker/` runtime.
- `worker-project-overmind-binding`: Durable worker binding moves from `ai/project_overmind.yaml` semantics to `.asdlc_worker/` runtime state rooted by `asdlc_worker.yaml`, while preserving the separation between durable project binding and per-run feature sync state.
- `orchestrator-worker-assigned-step-routing`: Orchestrator path resolution changes from root `ai/` paths to `.asdlc_worker/` paths one level below the worker repo root.
- `overmind-process-artifact-ownership`: Worker-owned process artifacts and runtime copies move under `.asdlc_worker/`, while source-of-truth ASDLC feature artifacts remain in the bound project repo.

## Impact

- Affected code:
  - new `ai/scripts/init_asdlc_worker.sh` source bootstrap script for installing/updating `.asdlc_worker/`
  - rename `ai/scripts/init_worker.sh` to `ai/scripts/register_worker.sh` for copied runtime worker registration/binding
  - `ai/scripts/orchestrator.sh`
  - `ai/scripts/ai_design.sh`
  - `ai/scripts/ai_plan.sh`
  - `ai/scripts/ai_implementation.sh`
  - `ai/scripts/ai_user_review.sh`
  - `ai/scripts/ai_audit.sh`
  - `ai/scripts/post_review.sh`
  - `ai/scripts/helpers/*` files that currently resolve paths relative to root `ai/`
- Affected tests:
  - `tests/ai_scripts/init_asdlc_worker_tests.sh`
  - rename or replace `tests/ai_scripts/init_worker_tests.sh` with `tests/ai_scripts/register_worker_tests.sh`
  - orchestrator, phase prompt, and helper tests that assert `ai/` paths
  - new init/update tests for target repo validation, `git init`, `.git/info/exclude` entries, overwrite scope, and preservation of non-generated `.asdlc_worker/` files
- Affected operator flow:
  - operators provide a target repo path to `ai/scripts/init_asdlc_worker.sh` from the YASDEF source checkout,
  - worker registration/binding is then run from `<target-repo>/.asdlc_worker/scripts/register_worker.sh`,
  - normal worker execution scripts are then run from `<target-repo>/.asdlc_worker/scripts/...`,
  - existing manually copied `ai/` runtimes require migration through the new init/update flow.
