# User Review Insights - Template

Use this schema when adding durable user-review rules to `ai/user_review.md`.

Rules:
- Write generalizable rules only (avoid one-off local fixes).
- If a new rule overlaps an existing UR entry, update the existing entry instead of adding a duplicate ID.
- If the required fields below cannot be populated with useful content, do not create a UR entry; record a step-specific note in the active step plan.

Required fields for each UR entry:
- **ID**: UR-XXXX
- **Status**: Accepted | Superseded
- **Date**: YYYY-MM-DD
- **Context**: Step or subsystem
- **Trigger**: Condition/pattern that should trigger the rule
- **Rule**: Normative guidance to follow
- **How to verify**: Concrete checks/tests/review steps to prove compliance
- **Example(s)**: Brief example of compliant behavior or implementation shape
- **References**: `path/to/file` `path/to/file`

Example block:
- **ID**: UR-0001
- **Status**: Accepted
- **Date**: 2026-03-03
- **Context**: User review phase
- **Trigger**: New durable review lesson is discovered from accepted feedback.
- **Rule**: Record only reusable review rules and keep one canonical entry per rule intent.
- **How to verify**: Confirm required fields are present and no overlapping Trigger+Rule exists under another UR ID.
- **Example(s)**: Update existing `UR-0001` with refined verification notes instead of adding `UR-0042` for the same rule.
- **References**: `ai/user_review.md` `ai/templates/user_review_TEMPLATE.md`
