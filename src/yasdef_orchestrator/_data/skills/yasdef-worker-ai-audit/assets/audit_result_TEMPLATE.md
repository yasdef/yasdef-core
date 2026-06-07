# AI audit result template

File: `.asdlc_worker/step_review_results/review_result-<step>-<feature-id>.md`

## Summary
- Step: `<step>`
- Feature: `<feature-id>`
- Branch / commit: `<branch and commit>`
- Scope reviewed: `<short scope summary>`

## Discovery Notes
- Findings must be derived only from: target-bullet proof gaps, scope drift, AGENTS.md invariant violations, and `//TODO` markers in changed files.
- Keep this artifact analysis-only. Do not record runtime code edits here.

## Findings

<!-- Add one `### F-NN` block per finding. The count is variable: zero findings is valid (omit all blocks); otherwise produce as many `### F-01`, `### F-02`, … `### F-NN` blocks as Phase 1 discovery surfaces. Keep IDs zero-padded and sequential. -->

### F-01
- Severity: `Critical|High|Medium|Low`
- Recommendation: `FollowupStep|RiseToCoordinator`
- Category: `TargetBulletNotProven|ScopeDrift|AgentsInvariant|TodoMarker`
- Target bullet / invariant:
- Reasoning:
- References:
  - `<path>:<line> (<symbol>)`
- Disposition state:
  - [ ] follow_up_created: `<step-id, e.g. 1.6a>`
  - [ ] raised_to_coordinator: `projects/<project>/<feature>/raised_questions/<step>-<worker-id>-F01.md`
  - [ ] rejected: `<optional rationale>`

### F-02
- Severity: `Critical|High|Medium|Low`
- Recommendation: `FollowupStep|RiseToCoordinator`
- Category: `TargetBulletNotProven|ScopeDrift|AgentsInvariant|TodoMarker`
- Target bullet / invariant:
- Reasoning:
- References:
  - `<path>:<line> (<symbol>)`
- Disposition state:
  - [ ] follow_up_created: `<step-id>`
  - [ ] raised_to_coordinator: `projects/<project>/<feature>/raised_questions/<step>-<worker-id>-F02.md`
  - [ ] rejected: `<optional rationale>`
