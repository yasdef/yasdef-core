## 1. Planning Baseline Fixture

- [x] 1.1 Add a local `test_post_review.py` helper that creates the canonical planning branch at the current worker baseline without changing the checked-out branch.
- [x] 1.2 Call the planning-baseline helper before review completion commits in the history-write, history-replacement, plan-sync-success, and plan-sync-failure scenarios.
- [x] 1.3 Leave the missing-review-artifact scenario minimal so it continues to prove artifact validation occurs before metrics collection.

## 2. Metrics Coverage

- [x] 2.1 Add a deterministic non-runtime file change after the planning baseline in one history scenario.
- [x] 2.2 Assert the rendered history records that post-planning change in its metrics without coupling the test to the complete history rendering.
- [x] 2.3 Confirm the four existing history and synchronization expectations remain unchanged and no production module is modified.

## 3. Verification

- [x] 3.1 Run `uv run --extra dev pytest -q tests/integration/test_post_review.py` and confirm all five scenarios pass.
- [x] 3.2 Run the full Python test suite and confirm the four Group 2 failures are removed, distinguishing any remaining CRP-142 partial-configuration failures until that change is implemented.
- [x] 3.3 Run the repository formatting, lint, and type checks applicable to the changed integration test file.
