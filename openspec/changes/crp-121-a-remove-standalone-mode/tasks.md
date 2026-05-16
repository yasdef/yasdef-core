## 1. Remove Standalone Codepath from `ai/scripts/orchestrator.sh`

- [x] 1.1 Delete the `STANDALONE_MODE=0` declaration at line 27
- [x] 1.2 Delete the `--standalone` case in the flag-parse switch (lines ~2974–2975)
- [x] 1.3 Delete the standalone banner emission block at lines ~3002–3004 (`if [[ "$STANDALONE_MODE" -eq 1 ]]; then ... echo "orchestrator: standalone mode enabled..." ... echo "orchestrator: standalone mode runtime inputs..." ...`)
- [x] 1.4 Delete the entire `ensure_standalone_runtime_context()` function (lines ~1295–1354)
- [x] 1.5 Replace the dispatch at lines ~1543–1544 with the unconditional default-mode path; delete the `if [[ "$STANDALONE_MODE" -eq 1 ]]; then ensure_standalone_runtime_context ...` guard
- [x] 1.6 Delete the `STANDALONE_MODE`-gated branches at lines ~828, ~976, ~1009, and ~2183; preserve only the default-mode body of each
- [x] 1.7 Strip the "or run .asdlc_worker/scripts/orchestrator.sh --standalone" suffix from the three `die` messages at lines ~985, ~988, ~991
- [x] 1.8 Remove the `[--standalone]` token from the `usage()` banner at line ~69
- [x] 1.9 Remove the `--standalone` description line at line ~83 from `usage()`
- [x] 1.10 Remove the `--standalone` example at line ~97 from `usage()`
- [x] 1.11 Run `grep -n "standalone\|STANDALONE" ai/scripts/orchestrator.sh` and confirm zero matches

## 2. Rewrite `tests/ai_scripts/user_review_phase_tests.sh` Without `--standalone`

- [x] 2.1 Inspect `tests/ai_scripts/orchestrator_assignment_tests.sh` for the canonical ASDLC binding fixture pattern (identity file, ASDLC source dir with `projects/<id>/<feature>/implementation_plan.md` + `reqirements_ears.md`, binding metadata)
- [x] 2.2 Rewrite the test at line ~225 to set up the full ASDLC binding fixture and invoke orchestrator without `--standalone`; preserve the assertion targets
- [x] 2.3 Rewrite the test at line ~248 the same way
- [x] 2.4 Rewrite the test at line ~268 the same way (note: this one uses output redirection to `/tmp/user-review-tests.out`)
- [x] 2.5 Rewrite the test at line ~288 the same way
- [x] 2.6 Rewrite the test at line ~333 the same way
- [x] 2.7 Rewrite the test at line ~375 the same way (note: this one redirects to `/tmp/user-review-invalid-ur.out`)
- [x] 2.8 Run `grep -n "standalone" tests/ai_scripts/user_review_phase_tests.sh` and confirm zero matches
- [x] 2.9 Run `bash tests/ai_scripts/user_review_phase_tests.sh` and confirm all tests pass

## 3. Delete Standalone-Dedicated Tests in `tests/ai_scripts/orchestrator_assignment_tests.sh`

- [x] 3.1 Delete the function `test_standalone_routes_from_local_overmind_runtime_and_skips_remote_validation` (starts at line ~625)
- [x] 3.2 Delete the function `test_standalone_fails_fast_when_local_runtime_ears_missing` (starts at line ~646)
- [x] 3.3 Delete the two corresponding dispatch lines at the bottom of the file (lines ~935–936)
- [x] 3.4 Delete the standalone-mention line at line ~261 ("The system SHALL support local standalone behavior.") if present in a comment block
- [x] 3.5 Run `grep -n "standalone" tests/ai_scripts/orchestrator_assignment_tests.sh` and confirm zero matches
- [x] 3.6 Run `bash tests/ai_scripts/orchestrator_assignment_tests.sh` and confirm all remaining tests pass

## 4. Update `Readme.md`

- [x] 4.1 Delete section **5.1 Workaround (`--standalone`)** at lines ~44–46
- [x] 4.2 Renumber any subsequent 5.x subsections if the deletion leaves gaps
- [x] 4.3 Delete the `--standalone` bullet in section 7 at line ~63
- [x] 4.4 Delete the "Standalone override" paragraph at line ~104
- [x] 4.5 Delete the change-history bullet at line ~248 ("add --standalone flag to allow orchestrator work without coordinator (overmind)")
- [x] 4.6 Run `grep -n "standalone\|--standalone" Readme.md` and confirm only references to the unrelated "standalone yasdef-overmind repo" prompt text (lines ~283, ~285) remain — those are about a separate repo, not the flag

## 5. Run the Full Orchestrator Test Suite

- [x] 5.1 Run every test file under `tests/ai_scripts/` and confirm all pass — Section 1/2/3 targets pass. Three tests fail (`implementation_evidence_tests.sh`, `orchestrator_debug_tests.sh`, `orchestrator_resume_tests.sh`); pre-existing failures on `v_0_1_4_patch` baseline, unrelated to this change (verified by re-running the same files with this change stashed — identical failures, only tmp paths differ).
- [x] 5.2 Manually invoke `bash ai/scripts/orchestrator.sh --standalone --dry-run` and confirm it exits non-zero with an "unknown option" error (proves the flag is fully gone) — exits non-zero, but with the default-mode runtime error rather than a literal "unknown option" message. The orchestrator's CLI parser pushes unrecognized tokens onto `PLAN_ARGS` (catch-all `*)` arm) instead of erroring, so `--standalone` is silently demoted to a plan-arg. The standalone codepath is gone; the flag has no effect. Strict rejection of unknown flags would be a separate behavior change and is out of scope.

## 6. Coordinate with Downstream Changes

- [x] 6.1 In `openspec/changes/crp-121-b-feature-qualified-step-branch-names/tasks.md`, remove every "when `SELECTED_FEATURE_ID` is non-empty" qualifier from tasks §1–§4 — also cleaned `design.md` and the two `specs/*/spec.md` files (dropped legacy-format fallback in extraction regex, dropped "Standalone step branches are not feature-qualified" / "Standalone step resume detection unchanged" scenarios). Remaining mentions of `non-empty` are explanatory text describing the new invariant.
- [x] 6.2 In `openspec/changes/crp-121-b-feature-qualified-step-branch-names/specs/orchestrator-worker-assigned-step-routing/spec.md`, delete the scenario "No feature identity passed for standalone step routing"
- [x] 6.3 Audit `openspec/changes/crp-122-feature-qualified-step-artifact-names/` for any "when non-empty" qualifiers and the same standalone-fallback scenarios; remove them — removed "Standalone step artifacts are not feature-qualified" scenario, "Step extracted from standalone plan filename is unchanged" scenario, and "Feature-qualified files are excluded from standalone latest resolution" scenario; cleaned matching language in `tasks.md` and `design.md`.
