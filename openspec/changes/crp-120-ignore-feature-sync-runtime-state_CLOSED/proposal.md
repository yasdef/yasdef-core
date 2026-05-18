## Why

`.asdlc_worker/feature_sync.yaml` is local runtime state, not durable project content, but today it participates in worktree dirtiness. That makes ordinary orchestrator reuse look like a branch change and can block branch switches or other git-based orchestration steps for reasons unrelated to feature implementation.

## What Changes

- Add `.asdlc_worker/feature_sync.yaml` to the local git exclude entries created by the ASDLC worker bootstrap/init flow.
- Define `feature_sync.yaml` as local runtime state that must remain available to orchestrator but must not be treated as branch content requiring commit/stash handling.
- Update init/bootstrap tests and operator docs to reflect that `feature_sync.yaml` is intentionally ignored by git cleanliness checks.
- Keep durable runtime files and selected-feature behavior unchanged; this change isolates only the git-visibility of the local feature-sync state file.

## Capabilities

### New Capabilities
- `feature-sync-local-runtime-ignore`: ASDLC worker initialization configures local git excludes so selected-feature runtime state does not dirty the worker repo.

### Modified Capabilities
- `worker-overmind-registration`: Worker bootstrap/init configures local runtime ignore rules for feature-sync state alongside other generated ASDLC runtime paths.

## Impact

- Affected bootstrap script:
  - `ai/scripts/init_asdlc_worker.sh`
- Affected tests:
  - `tests/ai_scripts/init_asdlc_worker_tests.sh`
- Affected docs/spec references:
  - `Readme.md`
  - initialization/bootstrap documentation describing local ASDLC runtime files
