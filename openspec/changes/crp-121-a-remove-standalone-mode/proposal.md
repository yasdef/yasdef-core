## Why

The orchestrator `--standalone` flag (introduced in crp-107) is an escape hatch for running phases against local `overmind/` runtime files when ASDLC source paths are unreachable. In practice it has become a source of conditional complexity: every downstream branch-naming and artifact-naming change (see `crp-121-b-feature-qualified-step-branch-names`, `crp-122-feature-qualified-step-artifact-names`) must add "when `SELECTED_FEATURE_ID` is non-empty" gating purely to preserve a legacy path that exists only because of standalone mode. Removing standalone gives us a simpler invariant — *feature context is always present* — and lets follow-on changes use feature-qualified naming unconditionally.

## What Changes

- **BREAKING**: Remove the `--standalone` flag from `ai/scripts/orchestrator.sh`. Operators must run with the full ASDLC binding.
- Delete `ensure_standalone_runtime_context()` and the `STANDALONE_MODE` variable from `ai/scripts/orchestrator.sh`.
- Remove all `STANDALONE_MODE`-gated branches in `ai/scripts/orchestrator.sh` (flag-parse case, mode banner emission, fast-path skip, dry-run validation skip, runtime context dispatch).
- After removal, `SELECTED_FEATURE_ID` is guaranteed non-empty whenever a step is selected (the `SELECTED_FEATURE_ID=""` reset inside the standalone context disappears with the function).
- Rewrite the five `--standalone` invocations in `tests/ai_scripts/user_review_phase_tests.sh` to use the full ASDLC binding fixture (the existing assignment-test fixture pattern in `tests/ai_scripts/orchestrator_assignment_tests.sh`).
- Delete the two dedicated standalone tests in `tests/ai_scripts/orchestrator_assignment_tests.sh`: `test_standalone_routes_from_local_overmind_runtime_and_skips_remote_validation` and `test_standalone_fails_fast_when_local_runtime_ears_missing`.
- Update `Readme.md`: remove the **5.1 workaround** section, the `--standalone` bullet in the run-the-orchestrator section, and the standalone change-history entry.

## Capabilities

### New Capabilities
<!-- None -->

### Modified Capabilities
- `orchestrator-worker-assigned-step-routing`: drop the standalone routing branch; routing always selects from the bound ASDLC feature flow.

### Removed Capabilities
- `orchestrator-standalone-mode`: the entire capability introduced by crp-107 is removed. No replacement — operators relying on this escape hatch must fix the ASDLC binding instead.

## Impact

- Affected runtime script:
  - `ai/scripts/orchestrator.sh`
- Affected tests:
  - `tests/ai_scripts/user_review_phase_tests.sh` (5+ invocations rewritten to use full ASDLC fixture)
  - `tests/ai_scripts/orchestrator_assignment_tests.sh` (2 standalone-dedicated tests removed)
- Affected docs:
  - `Readme.md` (sections 5.1, 7, and the change-history bullet on line 248)
- Affected operator flows:
  - Worker execution when ASDLC paths are unreachable: was a degraded local run, becomes a hard fail-fast. Operators must repair the binding to resume.
- Downstream impact:
  - `crp-121-b-feature-qualified-step-branch-names` and `crp-122-feature-qualified-step-artifact-names` can drop their "when `SELECTED_FEATURE_ID` is non-empty" gating and use feature-qualified naming unconditionally once this change lands first.
