# Feature design template

This file is the template for `ai/step_designs/step-<step>-design.md`.

Notes:
- Keep it concise and decision-focused.
- This artifact is for user review in the design phase.
- Include only feature-relevant rules from `AGENTS.md` and `ai/user_review.md`.
- For non-trivial scope, include 1-3 plan-critical items in `## Things to Decide (for final planning discussion)`; if none, write `- None.` with short rationale.

---

# Feature Design: <step> - <step title>
Date: <YYYY-MM-DD>
Designer model/session: <fill>

## Target Bullets (excluding planning/review)
- <target bullets from step (excluding planning/review)>

## Goal
- <one-sentence outcome>

## Non-goals
- <non-goal>

## In Scope
- <in scope>

## Out of Scope
- <out of scope>

## Things to Decide (for final planning discussion)
- <decision point with two clear alternatives and trade-off impact>
  - Option 1 (recommended): <default with rationale>
  - Option 2: <alternative with trade-off rationale>

## Trade-offs
- <trade-off>

## Proposal / Design Details
- <main design>

## Risks and Mitigations
- <risk> -> <mitigation>

## Quality and Testing
- <quality gates and planned tests>

## Alternatives
- <alternative> -> <why not chosen>

## Applicable ADR Shortlist (from ai/decisions.md)
- <ADR-xxxx — one-line relevance for this feature>
- None applicable for this feature. (use only when no ADR applies)

## Applicable AGENTS.md Constraints
- <relevant constraint>

## Applicable User Review Rules
- <UR-xxxx and short rationale>

## References in Current Codebase
Optional in design phase. Required for non-trivial behavior changes; otherwise include at least 1 reference.
- `<path>` - <why relevant>

## Unknowns / Assumptions to Validate (optional)
- <uncertainty or assumption to verify, or "None">
