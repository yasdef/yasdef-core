## Why

`ai/scripts/init_worker.sh` currently generates local worker identity, mutates the shared overmind registry, commits branch-local artifacts, and pushes remote changes. That flow is now too heavy for the worker side: worker registration is being handled on the overmind side first, so local worker initialization should only bind a developer workspace to an already-registered worker UUID and its overmind source.

## What Changes

- Refactor `ai/scripts/init_worker.sh` so it prompts the user for a worker UUID instead of generating or discovering one locally.
- Prompt the user for the path to the overmind source/workspace that owns the worker registration data.
- Require the script to fail fast with meaningful errors when:
  - the provided overmind path does not exist,
  - the provided path does not contain the expected worker-registration artifact for overmind-side onboarding,
  - the provided UUID is not already registered in that overmind source.
- Create a local `project_overmind.yaml` binding file containing:
  - the overmind source path,
  - the worker UUID,
  - the registered worker/project class,
  - the current worker status.
- Remove the current init-worker responsibilities that generate worker UUIDs, create `ai/<uuid>_dont_touch.txt`, register the worker in shared overmind state, commit registry updates, or push remote changes.
- Keep the broader worker branching strategy unchanged outside this narrower init flow.
- **BREAKING**: `ai/scripts/init_worker.sh` will stop auto-registering workers and stop persisting the legacy worker-id artifact layout.

## Capabilities

### New Capabilities
- `worker-project-overmind-binding`: Worker init SHALL create a local `project_overmind.yaml` binding artifact from an already-registered overmind worker entry, storing overmind source path, worker UUID, class, and current status.

### Modified Capabilities
- `worker-overmind-registration`: Worker init requirements SHALL change from generating/registering worker identity in shared overmind state to validating a user-provided UUID against an existing overmind-side worker registration source.
- `worker-identity-branch-split`: Worker init local-persistence requirements SHALL stop using `ai/<uuid>_dont_touch.txt` as the canonical artifact and SHALL preserve the existing branch strategy while switching the local onboarding artifact to `project_overmind.yaml`.

## Impact

- Affected code:
  - `ai/scripts/init_worker.sh`
- Affected tests:
  - `tests/ai_scripts/init_worker_tests.sh`
- Affected docs:
  - worker-init usage/documentation that currently describes automatic UUID generation and overmind registration
- Affected systems:
  - local worker onboarding state under `ai/`
  - validation against overmind-side worker registration data before local binding is created
