## 1. Process and prompt contract

- [ ] 1.1 Update `ai/AI_DEVELOPMENT_PROCESS.md` Section 5 to require a pre-dialogue linked-artifact self-check when the step plan has a non-empty `## Linked Artifacts (in scope)` block.
- [ ] 1.2 Define in Section 5 that linked-artifact drift means only incorrect implementation of touched current-step behavior, not missing untouched scope from larger linked artifacts.
- [ ] 1.3 Update Section 5 triage language so clear, objective linked-artifact drift is fixed before review dialogue, while ambiguous or unavailable linked content is surfaced in the Review Brief instead of creating a new hard gate.

## 2. User Review prompt generation

- [ ] 2.1 Extend `ai/scripts/ai_user_review.sh` to read `## Linked Artifacts (in scope)` from `ai/step_plans/step-<N>.md`.
- [ ] 2.2 Include the linked-artifact block in the user_review prompt packet only when the step plan carries one or more LAR entries.
- [ ] 2.3 Add prompt instructions stating that `## Plan (ordered)` remains the only phase-state source and linked artifacts are a non-hard correctness cross-check during the pre-dialogue self-check.
- [ ] 2.4 Add prompt instructions to fetch and compare linked artifacts for touched current-step behavior, auto-fix clear objective drift, rerun relevant verification, and surface ambiguous cases in the Review Brief as hotspots/questions.

## 3. Tests

- [ ] 3.1 Extend `tests/ai_scripts/user_review_phase_tests.sh` to verify the linked-artifact block is injected into the prompt when the step plan contains LAR entries.
- [ ] 3.2 Extend `tests/ai_scripts/user_review_phase_tests.sh` to verify the prompt preserves `## Plan (ordered)` as the only phase-state source and describes linked artifacts as a non-hard correctness cross-check.
- [ ] 3.3 Extend `tests/ai_scripts/user_review_phase_tests.sh` to verify empty or absent linked-artifact sections do not add unnecessary prompt instructions.
- [ ] 3.4 Run `bash tests/ai_scripts/user_review_phase_tests.sh` from the repo root and confirm the updated prompt contract passes.
