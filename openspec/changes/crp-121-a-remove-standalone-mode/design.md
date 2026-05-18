## Context

The orchestrator runs in two mutually exclusive runtime contexts today:

1. **Default (ASDLC-bound)**: orchestrator resolves a worker UUID, queries the overmind binding for candidate features, selects one, syncs runtime artifacts from that feature's branch, and routes the next assigned step. `SELECTED_FEATURE_ID` carries the chosen feature's identity.

2. **Standalone (`--standalone`)**: orchestrator skips feature discovery entirely, reads `overmind/implementation_plan.md` and `overmind/reqirements_ears.md` straight from the working tree, and explicitly sets `SELECTED_FEATURE_ID=""` to signal "no feature context."

Standalone was added in `crp-107-orchestrator-standalone-flag` as a temporary fallback for cases where ASDLC source paths were unreachable. Empirically, it has not earned its keep: there is no operational evidence that standalone has rescued a real run, and its presence has measurable cost. Every downstream change that wants to use feature identity in naming (branches in `crp-121-b`, artifact files in `crp-122`) has to add "when `SELECTED_FEATURE_ID` is non-empty" gating purely to keep the empty-string standalone path functional. That gating is duplicated across multiple call sites and has to be threaded through helper scripts (`ai_implementation.sh`, `ai_user_review.sh`, `ai_audit.sh`, `ai_plan.sh`).

The surface area in `ai/scripts/orchestrator.sh` is:

- Flag declaration: `STANDALONE_MODE=0` at line 27
- Flag parse case at lines 2974–2975
- Banner emission at lines 3002–3004
- Conditional branches at lines 828, 976, 1009, 1543, 2183
- Default-mode preflight error messages that reference `--standalone` at lines 985, 988, 991
- `ensure_standalone_runtime_context()` definition at lines 1295–1354 (~60 lines)
- Dispatch into the standalone context at lines 1543–1544
- Usage banner at lines 69, 83, 97

Plus tests and docs:

- `tests/ai_scripts/user_review_phase_tests.sh` uses `--standalone` as the test harness in five tests (lines 225, 248, 268, 288, 333, 375)
- `tests/ai_scripts/orchestrator_assignment_tests.sh` has two standalone-dedicated tests (lines 625, 646) plus their dispatch (lines 935–936)
- `Readme.md` references at lines 44–46, 63, 104, 248

## Goals / Non-Goals

**Goals:**
- Eliminate the standalone codepath so `SELECTED_FEATURE_ID` is structurally always non-empty after a successful selection.
- Replace the standalone-as-test-harness pattern in `user_review_phase_tests.sh` with the full ASDLC binding fixture, so user-review behavior is exercised under the only mode the orchestrator will continue to support.
- Update operator-facing docs to remove dead options.

**Non-Goals:**
- Do not change ASDLC binding behavior, feature discovery, or feature sync logic. Those keep working exactly as they do today in default mode.
- Do not change branch or artifact naming conventions — that is `crp-121-b` and `crp-122`.
- Do not add a replacement escape hatch. If a future incident demands one, design it then with real data.

## Decisions

### Decision 1: Hard removal, no deprecation period

Delete the flag, its parse case, and `ensure_standalone_runtime_context()` in one change. Do not introduce a deprecation warning or accept `--standalone` as a no-op.

**Why:** The flag has never been part of an external API contract. It is operator-facing only and the operator population is small. A deprecation window would force `crp-121-b` and `crp-122` to keep their conditional gating during the deprecation period, which defeats the point of removing standalone.

**Alternative considered:** Keep `--standalone` as a no-op that prints a deprecation warning for one release. Rejected because the downstream gating is the actual cost, not the user-facing flag itself.

### Decision 2: `user_review_phase_tests.sh` switches to the full ASDLC binding fixture

The five `--standalone` invocations in `user_review_phase_tests.sh` are using standalone as a shortcut to avoid setting up a worker UUID file, a binding, and a feature sync. Rewrite each test to set up the binding the same way `tests/ai_scripts/orchestrator_assignment_tests.sh` does: drop an `ai/<uuid>_dont_touch.txt` identity file, scaffold an ASDLC source directory with `projects/<id>/<feature>/implementation_plan.md`, and let the orchestrator do the normal sync.

**Why:** The user-review phase behavior under test is independent of whether the runtime files arrived via standalone or sync — the test is checking phase logic, not routing logic. Running it under the real routing flow strictly increases coverage rather than weakening it.

**Alternative considered:** Delete the five tests. Rejected because they cover real user-review phase scenarios (entry-gate validation, invalid UR detection) that are not duplicated elsewhere.

### Decision 3: Delete (don't migrate) the two `orchestrator_assignment_tests.sh` standalone tests

`test_standalone_routes_from_local_overmind_runtime_and_skips_remote_validation` and `test_standalone_fails_fast_when_local_runtime_ears_missing` are testing the standalone mode itself. With the mode gone, their subjects no longer exist.

**Why:** Nothing to migrate to — these tests assert "standalone mode emits banner X" and "standalone mode fails when ears file is missing." Both behaviors are being removed.

### Decision 4: Default-mode preflight errors lose their "or run --standalone" suffix

The three `die` messages at `ai/scripts/orchestrator.sh:985,988,991` currently end with "...or run .asdlc_worker/scripts/orchestrator.sh --standalone." Strip that clause.

**Why:** The suggestion will no longer be valid. Leaving it in would tell operators to use a non-existent flag.

### Decision 5: No new "REMOVED Requirements" delta for `orchestrator-standalone-mode` in main specs

The capability was introduced in `crp-107-orchestrator-standalone-flag` but that change was never archived into `openspec/specs/` (verified: `grep -rn "standalone" openspec/specs/` returns nothing). So there is no main-spec content to remove — the capability lives only inside the unarchived change folder.

**Why:** OpenSpec REMOVED deltas apply against `openspec/specs/<capability>/spec.md`. With no main spec for `orchestrator-standalone-mode`, the proposal-level "Removed Capabilities" note is the correct artifact; we do not author a delta against a non-existent main spec.

**How this is recorded:** `proposal.md` lists `orchestrator-standalone-mode` under Removed Capabilities. The spec deltas in this change touch only `orchestrator-worker-assigned-step-routing`.

## Risks / Trade-offs

- **[Risk]** An operator with a broken ASDLC binding loses the local-only fallback and is fully blocked until the binding is repaired. → **Mitigation:** the default-mode preflight already emits explicit fail-fast errors at lines 985/988/991 pointing at what's wrong (missing worktree, missing branch, missing upstream). Operators have actionable diagnostics; they no longer have a way to bypass them.
- **[Risk]** `user_review_phase_tests.sh` rewrite is the bulk of the diff and could introduce test-fixture bugs that mask real regressions. → **Mitigation:** reuse the established fixture builders from `orchestrator_assignment_tests.sh` rather than inventing new helpers; assert the same observable outcomes the original tests asserted (same stdout/stderr patterns, same branch-state checks).
- **[Trade-off]** Loss of operational flexibility for the sake of code simplicity. Accepted because the cost of the flexibility (gating in every downstream naming change) is concrete and recurring, while the benefit (an escape hatch that has never been needed) is hypothetical.
- **[Risk]** `crp-121-b` and `crp-122` already have their proposal/spec/tasks artifacts authored with the "when non-empty" gating language. After this change lands they must be updated. → **Mitigation:** call this out in this proposal's Impact section so the operator applying changes in order knows to revise crp-121-b and crp-122 before implementing them.

## Migration Plan

1. Land this change (`crp-121-a`).
2. Revise `crp-121-b-feature-qualified-step-branch-names` artifacts: remove all "when `SELECTED_FEATURE_ID` is non-empty" guards from tasks.md and the corresponding scenarios from specs (e.g. the "No feature identity passed for standalone step routing" scenario in `specs/orchestrator-worker-assigned-step-routing/spec.md`).
3. Revise `crp-122-feature-qualified-step-artifact-names` artifacts the same way.
4. Then implement `crp-121-b` and `crp-122` against the simplified invariant.

**Rollback:** revert this change. The `--standalone` codepath returns intact, and `crp-121-b`/`crp-122` artifacts (if not yet implemented) are unaffected.

## Open Questions

None — operator decision (drop the escape hatch in favor of a simpler invariant) is already made.
