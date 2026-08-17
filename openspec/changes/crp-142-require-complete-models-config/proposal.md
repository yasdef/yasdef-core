## Why

`yasdef run` currently accepts partial `.asdlc_worker/setup/models.md` configurations, starts the configured subset, and then fails indirectly when the internally appended `post_review` phase cannot find artifacts that omitted upstream phases would have produced. Partial phase execution is not a supported product mode, so invalid configuration must be rejected explicitly before feature selection, branch creation, or model execution.

## What Changes

- Add startup validation requiring the complete model-driven phase set: `design`, `planning`, `implementation`, `user_review`, `ai_audit`; row order does not configure workflow order.
- Reject missing, duplicate, malformed, unavailable, or unreadable configuration with actionable diagnostics, while preserving existing unknown-phase and `post_review` rejection.
- Keep `post_review` outside `models.md` and append it internally only after the complete model-driven phase set validates.
- Make the existing clean-mainline gate unconditional for non-resume runs because every supported run starts with `design`; resume runs retain their current exemption.
- Replace the design-only integration helper with a complete echo configuration, retain early-exit tests that never enter a phase, and rework only successful partial-pipeline scenarios into supported focused coverage.
- Correct the technical-improvement record so it distinguishes the seven partial-pipeline failures from the separate post-review metrics-fixture failures.

## Capabilities

### New Capabilities

- `worker-model-pipeline-configuration`: Defines complete worker `models.md` membership, canonical execution order, early validation and mainline boundaries, diagnostics, and the supported test contract.

### Modified Capabilities

_None._

## Impact

- `src/yasdef_worker/domain/models_config.py`: strict active-row parsing and complete-pipeline validation.
- `src/yasdef_worker/app/coordinator.py`: handles configuration-read errors, validates before the mainline policy and other run side effects, uses canonical workflow order, and applies the clean-mainline gate to every non-resume run.
- `src/yasdef_worker/app/mainline_branch_policy.py`: behavior is unchanged, but its `require_clean_mainline_start` policy becomes unconditional for non-resume coordinator runs.
- `src/yasdef_worker/domain/phases.py`: remains the canonical source for required model and workflow phase order.
- `tests/unit/domain/test_branches_models.py`, `tests/unit/app/test_coordinator.py`, and `tests/integration/test_run.py`: rewrite partial-configuration fixtures and remove the unsupported non-design-run premise while preserving focused behavior coverage.
- `src/yasdef_worker/_data/setup/models.md`: already contains all required phases and needs no content change; fresh installs remain valid.
- `Readme.md` and `design_docs/improvement_proposals/technical_improvements.md`: clarify that phase rows configure runner/model selection, the complete phase set is mandatory, and execution order is canonical.
- No new CLI flags, dependencies, or partial-run mode.
