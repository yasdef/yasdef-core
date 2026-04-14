## ADDED Requirements

### Requirement: user_review SHALL create only canonical YASDEF TODO markers
When `user_review` adds inline TODO markers for unresolved blockers, it MUST use only the canonical format `TODO YASDEF [BLK-<id>] [phase:user_review|ai_audit]: <reason>`.

#### Scenario: Canonical marker creation
- **WHEN** `user_review` identifies an unresolved blocker that needs follow-up work
- **THEN** it creates an inline marker using the exact canonical token sequence with blocker ID, phase tag, and concise reason

#### Scenario: Non-canonical marker blocked
- **WHEN** a proposed marker omits `YASDEF`, blocker ID, phase tag, or reason
- **THEN** `user_review` MUST treat that marker as invalid and replace it with canonical format before finalizing output

### Requirement: user_review SHALL create markers only for concrete unresolved blockers
`user_review` MUST create canonical TODO markers only for concrete unresolved blockers and MUST NOT create them for non-blocking polish or speculative ideas.

#### Scenario: Blocking issue creates marker
- **WHEN** a review issue cannot be resolved within the current review loop and requires tracked follow-up
- **THEN** `user_review` adds a canonical marker linked to that blocker

#### Scenario: Non-blocking issue does not create marker
- **WHEN** review feedback is a non-blocking improvement or optional polish item
- **THEN** `user_review` MUST NOT create a canonical TODO marker for that feedback

### Requirement: user_review SHALL enforce blocker-log linkage for each marker
Each canonical TODO marker created in `user_review` MUST map to exactly one blocker entry in `ai/blocker_log.md` using the same `BLK-<id>`.

#### Scenario: Marker and blocker entry are linked
- **WHEN** `user_review` creates a canonical marker with `BLK-123`
- **THEN** `ai/blocker_log.md` contains a corresponding blocker entry for `BLK-123` describing the same unresolved issue

#### Scenario: Missing blocker entry is rejected
- **WHEN** a canonical marker is present without matching blocker-log entry
- **THEN** `user_review` output is non-compliant until linkage is restored

### Requirement: user_review SHALL preserve handoff readiness for ai_audit TODO-to-finding conversion
Markers created by `user_review` MUST remain structured for deterministic conversion into findings by `ai_audit` Section 6.1.

#### Scenario: Marker is ready for audit conversion
- **WHEN** `ai_audit` starts Section 6.1 TODO analysis
- **THEN** each marker created in `user_review` can be converted into a finding using blocker ID, phase, reason, and source context

#### Scenario: Handoff references are explicit
- **WHEN** process artifacts describe user_review marker behavior
- **THEN** they explicitly state that canonical markers are handed off to `ai_audit` Section 6.1 for finding conversion
