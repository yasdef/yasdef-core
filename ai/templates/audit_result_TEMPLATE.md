# Step ai_audit result template

File: `ai/step_review_results/review_result-<current_step>.md`

## Summary
- Step: `<current_step>`
- Scope: `<what was reviewed>`
- Branch / commit: `<branch name and/or last commit>`

## Entry Proof Check (Section 6.0)
- Target bullet: `<copied from ai/implementation_plan.md>` — **PROVEN** | **NOT_PROVEN**
  - Code refs: `<path + key symbol>`
  - Reachability: `<entrypoint-first flow>`
  - Test evidence: `<new/updated test or credible existing coverage mapping>`
- Repeat for each in-scope target bullet.
- If any bullet is **NOT_PROVEN**, record it and stop deeper audit analysis until disposition guidance is provided.

## Critical
- (none)

## High
- (none)

## Medium
- (none)

## Low
- (none)

## Disposition (per issue)
For each issue above, record one of:
- **Accepted**: `<what follow-up work was created and where (implementation_plan / open_questions / blocker_log)>`
- **Rejected**: `<brief rationale>`
