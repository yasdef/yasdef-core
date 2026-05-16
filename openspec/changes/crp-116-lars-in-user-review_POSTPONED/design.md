## Context

This repo already has a linked-artifact flow for design, planning, and implementation. The design phase funnels step-scoped `LAR-NNN` references from `overmind/reqirements_ears.md` into `## Linked Artifacts (in scope)`. Planning mirrors that shortlist into the step plan and uses the linked sources as one more context input. Implementation reads the shortlist from the step plan and treats fetched linked artifacts as source-of-truth inputs for fidelity-sensitive details.

The remaining gap is inside `user_review`. Section 5 already requires a pre-dialogue self-check against the step plan, translated requirements, design scope, accepted decisions, `AGENTS.md`, and `ai/user_review.md` rules. It does not yet require the reviewer to re-check touched implementation details against the step plan's linked-artifact shortlist when that shortlist is present. That means a step can enter review with correct ordered-plan closure while still drifting from a linked prototype or contract in the exact area the step changed.

The implementation surface for this change is intentionally narrow:
- `ai/AI_DEVELOPMENT_PROCESS.md` Section 5 needs a new rule for the pre-dialogue self-check.
- `ai/scripts/ai_user_review.sh` needs to read and emit the linked-artifact block from the step plan when present and state the new self-check rule in the prompt packet.
- `tests/ai_scripts/user_review_phase_tests.sh` needs prompt-contract coverage for present/absent LAR blocks and the non-hard drift semantics.

## Goals / Non-Goals

**Goals:**
- Make `user_review` explicitly re-check touched implementation details against linked artifacts before asking the user for feedback.
- Preserve `## Plan (ordered)` as the only `user_review` phase-state contract.
- Keep linked-artifact checking scope-limited to behavior the current step changed or relied on.
- Treat linked-artifact drift as a fix-if-clear pre-review issue, not as a new hard readiness gate.
- Surface ambiguous or non-obvious linked-artifact mismatches in the Review Brief as targeted hotspots/questions.

**Non-Goals:**
- No new `user_review` readiness helper or hard-fail gate tied to linked artifacts.
- No expansion of review scope to untouched parts of large prototypes or documents.
- No change to planning or implementation linked-artifact behavior.
- No change to `ai_audit`, `post_review`, or OpenSpec apply/archive flows.
- No new CLI flags, prompt modes, or artifact types.

## Decisions

### Decision 1: Use the step plan's linked-artifact shortlist as the only user-review LAR source

`user_review` will consume `## Linked Artifacts (in scope)` from `ai/step_plans/step-<N>.md`, not by re-deriving from `overmind/reqirements_ears.md` and not from the design artifact. This matches the existing mid-phase contract: user review already uses the step plan as its execution/requirement packet.

Rationale: this preserves the existing phase-boundary model. The linked-artifact shortlist has already been funneled and mirrored upstream, so user_review should consume the same packet rather than opening a second derivation path.

Alternative considered: source linked artifacts from the design artifact. Rejected because user_review already uses the step plan as its current-step contract, and the step plan is the narrower, implementation-adjacent artifact.

### Decision 2: The linked-artifact check is a correctness cross-check, not a second state machine

The prompt and process language will say explicitly that `## Plan (ordered)` remains the only phase-state source. The linked-artifact block is used only to verify that the behavior/details touched by the current step do not contradict the linked sources.

Rationale: the user asked for correctness help, not a second completion checklist. Keeping this boundary explicit prevents user_review from drifting back toward coordinator-artifact or prototype-driven state management.

Alternative considered: require linked-artifact proof before user_review can start. Rejected because it would create a new hard gate and blur the distinction between execution state and review-quality checks.

### Decision 3: Define drift narrowly around touched behavior

For this change, linked-artifact drift means the current-step implementation contradicts or misimplements artifact-backed details for behavior the step actually changed or depended on. It does not mean the linked artifact contains additional screens, states, or details that remain out of scope for the step.

Rationale: without this boundary, any non-trivial design document or prototype would continually pressure the reviewer to expand scope. The definition needs to align with current-step intent, not total artifact completeness.

Alternative considered: compare the implementation against the full linked artifact and report all differences. Rejected because it would conflate omission of out-of-scope work with incorrect implementation.

### Decision 4: Auto-fix only clear, objective drift

When the linked source clearly shows that the changed implementation is wrong in a concrete, current-scope way, the self-check should fix it before asking the user for review and rerun the relevant verification. When the linked source is ambiguous, unavailable, or suggests a mismatch that is not safe to resolve automatically, user_review should not hard-fail. Instead it should highlight the issue in the Review Brief as a focused hotspot/question.

Rationale: this matches the existing Section 5 triage rule: fix clear objective findings early, but do not silently choose through ambiguity.

Alternative considered: always ask the user before fixing any linked-artifact mismatch. Rejected because it would undercut the value of the self-check for obvious fidelity mistakes.

### Decision 5: Keep the prompt contract conditional on a non-empty linked-artifact section

`ai/scripts/ai_user_review.sh` will include the linked-artifact section and the new self-check instruction only when the step plan carries a non-empty `## Linked Artifacts (in scope)` block. Empty or absent sections remain a no-op.

Rationale: most steps likely do not use linked artifacts. The prompt should stay lean and unchanged for those cases.

Alternative considered: always emit a generic linked-artifact instruction. Rejected because it adds noise and implies extra work even when no LARs are in scope.

## Risks / Trade-offs

- **Risk:** The reviewer may over-interpret the linked artifacts and treat unimplemented surrounding details as drift.
  - **Mitigation:** define drift narrowly in both the process doc and prompt contract around touched behavior only.

- **Risk:** The linked artifact is reachable but ambiguous, stale, or partially unreadable, producing noisy review hotspots.
  - **Mitigation:** keep the check non-hard and route ambiguous cases into the Review Brief rather than blocking the phase.

- **Risk:** The prompt grows and duplicates too much linked-artifact context.
  - **Mitigation:** include only the existing step-plan shortlist, not re-fetched summaries or a second artifact registry.

- **Risk:** Reviewers may mistake the new check for a new completion gate and stop trusting `## Plan (ordered)` as the phase-state source.
  - **Mitigation:** explicitly preserve the current wording that `## Plan (ordered)` is the only phase-state source and state that the LAR check is a correctness cross-check only.

- **Risk:** Clear linked-artifact drift fixes in self-check may require extra verification cycles, lengthening the review handoff slightly.
  - **Mitigation:** this is acceptable because the correction happens before the user spends time reviewing known-bad output.

