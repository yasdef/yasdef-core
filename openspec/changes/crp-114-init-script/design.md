## Context

Current worker setup assumes the YASDEF `ai/` directory is already present at the target repository root. Scripts derive `ROOT` from `ai/scripts`, store durable state in `ai/project_overmind.yaml`, write prompts/logs under `ai/`, and operate on local runtime copies under `overmind/`. This makes the YASDEF source checkout and a manually copied worker runtime look structurally identical, so users can accidentally run scripts from the wrong repository.

CRP-114 changes the model to an explicit bootstrap/update flow. YASDEF remains the source distribution, while each target repository gets a generated `.asdlc_worker/` runtime folder. `ai/scripts/init_asdlc_worker.sh` is the source-side installer/updater. The copied runtime worker-binding script is renamed from `init_worker.sh` to `register_worker.sh`, and copied runtime scripts must run against the target repo parent, not against the YASDEF checkout.

## Goals / Non-Goals

**Goals:**

- Provide one init/update entry point that installs YASDEF worker runtime files into a user-selected target repo.
- Rename the copied worker-binding command to `register_worker.sh` so it is not confused with source-side runtime initialization.
- Make target repo validation deterministic before any files are copied.
- Support target repos with no git metadata by running `git init`.
- Reject paths inside another git repo when the selected path is not that repo root.
- Make `.asdlc_worker` the runtime home for scripts, templates, process docs, logs, prompts, and worker-local state.
- Make the parent of `.asdlc_worker` the worker repo root for project code, git branches, and source edits.
- Preserve non-generated `.asdlc_worker/` state during update mode.

**Non-Goals:**

- No backward compatibility for running scripts from a root-level `ai/` folder.
- No new CLI flags for worker scripts unless already required by existing contracts.
- No migration of source-of-truth ASDLC feature artifacts; they remain in the bound project repo.
- No change to model selection semantics beyond path relocation.

## Decisions

### Decision 1: Split runtime home from worker repo root

Scripts will resolve two roots:

- `ASDLC_WORKER_HOME=<target-repo>/.asdlc_worker`
- `WORKER_REPO_ROOT=<target-repo>`

Runtime-owned inputs and outputs such as `AI_DEVELOPMENT_PROCESS.md`, `templates/`, `golden_examples/`, `setup/`, `prompts/`, `logs/`, `project_overmind.yaml`, `feature_sync.yaml`, `decisions.md`, `blocker_log.md`, `open_questions.md`, `user_review.md`, `history.md`, `step_plans/`, `designs/`, and `step_review_results/` live under `ASDLC_WORKER_HOME`. Project code, branch operations, and all implementation edits use `WORKER_REPO_ROOT`.

Alternative considered: keep `ai/` as runtime home and add a marker file. Rejected because the operator specifically wants scripts to be impossible to run from the YASDEF repo layout, and a distinct `.asdlc_worker` directory makes that boundary testable.

### Decision 2: Add shared shell path resolution

Scripts and helpers should use one shared shell helper for layout validation and path derivation instead of each script recomputing `ROOT` differently. The helper should:

- resolve the current script directory,
- require the script to be under `<repo-root>/.asdlc_worker/scripts` or `<repo-root>/.asdlc_worker/scripts/helpers`,
- export or print `ASDLC_WORKER_HOME` and `WORKER_REPO_ROOT`,
- fail fast with a clear unsupported-layout message.

Alternative considered: patch each script independently. Rejected because current scripts already mix several path-resolution patterns, and duplicating the new logic would make drift likely.

### Decision 3: Bootstrap copies generated runtime subsets, update mode overwrites only generated subsets

The init script will copy YASDEF `ai/` runtime content into `.asdlc_worker/`. On update, it overwrites only generated runtime folders/files named in the proposal and preserves all other files. This protects repo-local worker binding and run state while still allowing process scripts/templates to update.

Alternative considered: delete and recreate `.asdlc_worker/` during update. Rejected because it would destroy local binding, feature sync, history, decisions, and in-flight work artifacts.

### Decision 4: Use `.git/info/exclude` for generated runtime files

The init script will add generated runtime-only entries to the target repo's `.git/info/exclude`, idempotently. This keeps generated YASDEF runtime implementation details out of the target repo by default without mutating project-level `.gitignore`.

Alternative considered: write `.gitignore` entries. Rejected because `.gitignore` is project-owned and could create review noise in unrelated application repos.

### Decision 5: Separate bootstrap init from worker registration

The source repository will provide `ai/scripts/init_asdlc_worker.sh` for installing or updating `.asdlc_worker/` in a target repo. The copied runtime command currently known as `init_worker.sh` will be renamed to `register_worker.sh` because its job after this change is to bind/register the already-installed runtime to an existing ASDLC worker UUID and project registry entry.

Alternative considered: keep `init_worker.sh` and add a new bootstrap script. Rejected because two commands with "init" semantics would make operator instructions ambiguous.

## Risks / Trade-offs

- [Risk] Many tests and prompt assertions hard-code `ai/` paths. -> Mitigation: update tests in focused groups and keep compatibility expectations intentionally broken where the old layout is rejected.
- [Risk] Update mode may overwrite user edits inside generated folders. -> Mitigation: keep the generated overwrite set explicit and preserve all non-generated `.asdlc_worker/` paths.
- [Risk] Runtime state relocation can break resume behavior. -> Mitigation: keep filenames and state semantics stable while changing their base directory.
- [Risk] Existing users with manually copied `ai/` folders need migration. -> Mitigation: fail fast with a clear unsupported-layout message.

## Migration Plan

1. Add `ai/scripts/init_asdlc_worker.sh` bootstrap/update behavior and tests for target repo validation, `git init`, `.asdlc_worker/` copy scope, and `.git/info/exclude`.
2. Rename `ai/scripts/init_worker.sh` to `ai/scripts/register_worker.sh` and update tests/callers.
3. Add shared layout resolution helper and convert orchestrator, phase scripts, registration script, and helpers to use it.
4. Move runtime state path references from `ai/...` to `.asdlc_worker/...` and code/project references to the worker repo root.
5. Remove or update tests that rely on root `ai/` runtime execution.

Rollback strategy: restore root `ai/` path resolution in scripts, rename `register_worker.sh` back to `init_worker.sh`, remove the bootstrap/update install path, and stop adding `.asdlc_worker` entries to target repo excludes. Any already-created `.asdlc_worker/` directories can be removed manually from target repos.

## Open Questions

- Should durable state files such as `project_overmind.yaml` be renamed immediately, or should filenames remain stable under `.asdlc_worker/` for lower migration risk?
