## ADDED Requirements

### Requirement: Review Brief SHALL surface unresolved linked-artifact ambiguity as a targeted hotspot
When the User Review self-check finds a linked-artifact mismatch that is not safe to auto-fix because the linked content is ambiguous, unavailable, or would require a new user decision, the Review Brief MUST call out that issue as a targeted hotspot or question before asking for user feedback.

#### Scenario: Review Brief highlights unresolved linked-artifact concern
- **WHEN** User Review reaches the Review Brief after finding an unresolved linked-artifact concern during self-check
- **THEN** the Review Brief explicitly lists that concern under what should be checked first
- **THEN** the prompt for user feedback comes only after the concern is surfaced

