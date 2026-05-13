## Why

`ai/scripts/init_worker.sh` can bind a worker to a project before the local worker repo has project-specific AI guidance. Because the script already knows the worker class before switching to `overmind`, it should use that moment on the current branch to remind the operator to create root `AGENTS.md` guidance, optionally pointing at the class-specific project blueprint.

## What Changes

- Add a pre-branch-switch guidance check in `ai/scripts/init_worker.sh` after the registered worker class is resolved and before `checkout_or_create_overmind_branch`.
- Check the local worker repo root, defined as the directory one level above `ai/`, for root-level `AGENTS.md`.
- Check the bound ASDLC project repo root, the same directory that contains `init_progress_definition.yaml`, for `project_stack_blueprint_<project_class>.md`, using the resolved worker class from `workers.yaml`.
- If root `AGENTS.md` is missing and the class-specific blueprint exists, print:
  - `⚠️  before start implementing things, ask model to create AGENTS.md, pass <path-to-blueprint> to your prompt so model can use best practices`
- If root `AGENTS.md` is missing and the class-specific blueprint is absent, print:
  - `⚠️  before start implementing things, dont forget to create AGENTS.md`
- If root `AGENTS.md` exists, do not print either warning.
- Do not fail initialization for missing `AGENTS.md` or missing blueprint.
- Do not add script CLI flags or options.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `worker-overmind-registration`: worker initialization SHALL perform a non-blocking root `AGENTS.md` guidance check after resolving worker class metadata and before switching to branch `overmind`.
- `project-agent-guidance`: project guidance behavior SHALL include an init-time reminder when the worker repo lacks root `AGENTS.md`, using a class-specific project blueprint path when available.

## Impact

- Affected code:
  - `ai/scripts/init_worker.sh`
- Affected tests:
  - `tests/ai_scripts/init_worker_tests.sh`
- Affected docs:
  - `Readme.md` or nearby worker-init guidance if operator-facing setup text needs to mention the warning behavior.
- Affected operator flow:
  - Successful worker initialization may now print a non-blocking warning before switching to `overmind` when root `AGENTS.md` is absent.
