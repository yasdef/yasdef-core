# Feature design template

This file is the template for `ai/step_designs/step-<step>-design.md`.

Notes:
- Keep it concise and decision-focused.
- This artifact is for user review in the design phase.
- Include only feature-relevant rules from `AGENTS.md` and `ai/user_review.md`.
- For non-trivial scope, include 1-3 plan-critical items in `## Things to Decide (for final planning discussion)`; if none, write `- None.` with short rationale.
- Add `## First-Feature Bootstrap (only if needed)` only when bootstrap handoff is needed for this step.

---

# Feature Design: <step> - <step title>
Date: <YYYY-MM-DD>
Designer model/session: <fill>

## Target Bullets (excluding planning/review)
- <target bullets from step (excluding planning/review)>

## Selected EARS Requirements (for planning translation)
- <selected EARS requirement excerpts used to translate step-plan functional requirements>

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

## Linked Artifacts (in scope)
- <LAR-NNN | type | title | locator> (omit or leave empty when no LARs are in scope for this step)

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

## First-Feature Bootstrap (only if needed)
<Replace this line only when bootstrap handoff is needed.>
- Bootstrap required: yes|no
- Blueprint result: <relevant blueprint found / no relevant blueprint found / irrelevant blueprint(s) only / blocked by missing class metadata>
- Blueprint evidence: <path(s) or "None">
- User stack decision: <approved stack/scaffold choice or "None">
- Planning handoff: <state scaffold creation must be first in planning, plus scaffold constraints/deliverable>
