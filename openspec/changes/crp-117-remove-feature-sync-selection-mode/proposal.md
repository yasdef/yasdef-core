## Why

`selection_mode` in `.asdlc_worker/feature_sync.yaml` no longer serves as a routing decision input, but it is still rewritten during feature reuse. That creates recursive `resume_reuse` prefixes, produces unnecessary local state churn, and makes the overmind runtime branch look dirty for metadata-only reasons.

## What Changes

- Remove `selection_mode` from the `feature_sync.yaml` schema and stop reading or writing it in orchestrator feature-selection and resume flows.
- Keep feature reuse validation based on the fields that actually determine correctness: project identity, worker identity, runtime branch, source paths, and assigned-step validity.
- Update tests, docs, and examples so `feature_sync.yaml` is documented as selected-feature state without `selection_mode`.
- Preserve current feature-selection behavior otherwise; this change is schema cleanup, not a routing-policy rewrite.

## Capabilities

### New Capabilities
- `feature-sync-schema-without-selection-mode`: The worker runtime stores selected-feature metadata without a `selection_mode` field and without recursive reuse provenance embedded in the state file.

### Modified Capabilities
- `orchestrator-step-resume`: Resume reuse of selected-feature context no longer depends on or mutates `selection_mode` metadata.
- `orchestrator-worker-assigned-step-routing`: Feature-sync metadata written during routing omits `selection_mode` while preserving the rest of the selected-feature contract.

## Impact

- Affected runtime script:
  - `ai/scripts/orchestrator.sh`
- Affected tests:
  - `tests/ai_scripts/orchestrator_assignment_tests.sh`
  - `tests/ai_scripts/orchestrator_resume_tests.sh`
- Affected docs/spec references:
  - `Readme.md`
  - OpenSpec artifacts that still describe `selection_mode` as part of `feature_sync.yaml`
