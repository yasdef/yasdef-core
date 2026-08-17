## Why

Four post-review integration tests construct a worker repository without the planning branch required by the current default metrics range, so they fail before reaching the history and plan-sync behavior they intend to verify. The production workflow already creates this baseline; the test fixtures must represent that supported process.

## What Changes

- Update post-review integration setup to create the canonical `step-<step>-<feature-id>-plan` branch before later workflow commits.
- Preserve the current product behavior that calculates default metrics from the planning baseline through `HEAD`.
- Keep the existing history creation, history replacement, successful plan-sync, and failed plan-sync expectations.
- Add focused assertions that demonstrate the fixture supplies a valid metrics range and post-review measures changes after planning.
- Make no production-code or CLI behavior changes.

## Capabilities

### New Capabilities

_None. This change corrects test infrastructure and does not introduce product behavior._

### Modified Capabilities

_None._

## Impact

- `tests/integration/test_post_review.py`: create a realistic planning baseline and use it in the four affected scenarios.
- Potentially `tests/integration/conftest.py`: add a narrowly reusable Git-history helper only if the same setup is needed across multiple integration modules.
- No runtime modules, public interfaces, dependencies, or persisted formats change.
