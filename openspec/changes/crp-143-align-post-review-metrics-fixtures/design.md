## Context

See `proposal.md` for motivation. `PostReviewOperation` defaults to the Git range `step-<step>-<feature-id>-plan..HEAD`. A normal pipeline creates that planning branch before implementation and review commits, but the post-review integration fixtures currently create only the worker's initial branch and a committed review artifact.

The integration tests use real temporary Git repositories through helpers in `tests/integration/conftest.py`. Test setup must preserve the repository-level invariants in `AGENTS.md` and must not weaken runtime behavior to accommodate an artificial history.

## Goals / Non-Goals

**Goals:**
- Represent the planning baseline and later workflow commits with a minimal, deterministic Git topology.
- Restore the four intended history and plan-sync scenarios.
- Verify that default metrics can resolve the canonical planning-to-`HEAD` range.

**Non-Goals:**
- Change post-review metrics selection, error handling, CLI arguments, or runtime branch naming.
- Make a missing planning branch valid.
- Expand these tests into full model-phase pipeline tests.
- Address the separate partial-`models.md` integration failures covered by CRP-142.

## Decisions

### Create the planning branch before review completion commits

Add a test helper that creates `step-<step>-<feature-id>-plan` at the worker repository's baseline commit while leaving the current branch checked out. Call it before `_write_review_artifact`, so the artifact and any product-file changes are later commits reachable from `HEAD` but not from the planning baseline.

This directly reproduces the topology expected by production. The helper should use the existing branch-naming domain function so fixture naming stays aligned with runtime naming.

Alternative considered: pass `--metrics-ref HEAD` from every test. Rejected because it bypasses the default behavior and would allow the production planning-range contract to regress unnoticed.

Alternative considered: create and check out every intermediate workflow branch. Rejected because post-review only requires the planning baseline and `HEAD`; extra branches add setup complexity without improving these tests.

### Keep fixture ownership local unless reuse is demonstrated

Place the planning-baseline helper in `test_post_review.py` unless another integration module immediately needs the same topology. This keeps the shared `conftest.py` API small and makes the prerequisite visible beside the tests that depend on it.

Alternative considered: add the helper to `ScenarioFactory`. Rejected because these standalone post-review tests do not require a complete coordinator scenario.

### Prove the range with one non-runtime change

Add or adapt one history scenario to commit a small non-`.asdlc_worker` file after the planning branch and assert the resulting history metrics. The review artifact itself is intentionally excluded by `MetricsCollector`, so relying only on that artifact would prove range resolution but not correct measurement.

The remaining scenarios retain their existing assertions. They all use the same valid baseline setup, ensuring history replacement and plan synchronization are reached instead of failing during metrics collection.

## Risks / Trade-offs

- [The fixture branch accidentally points at the review commit] -> Create the branch before `_write_review_artifact` and assert a post-baseline product change is counted.
- [A shared helper hides important scenario setup] -> Keep the helper local and name it explicitly around the planning metrics baseline.
- [Tests become coupled to incidental metric formatting] -> Assert stable numeric behavior, not the complete rendered history block.
- [The full suite remains red until CRP-142 is implemented] -> Require the focused post-review integration module to pass and distinguish any remaining known partial-configuration failures during interim verification.

## Migration Plan

1. Add the local planning-baseline fixture helper.
2. Apply it to the four post-review scenarios that proceed beyond artifact validation.
3. Add one post-planning product change and metric assertion.
4. Run the focused post-review integration tests, then the full Python suite to confirm Group 2 is removed.

Rollback removes only the test-fixture changes; no runtime or persisted data migration is involved.
