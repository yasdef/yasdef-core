# Feature design (golden example)

# Feature Design: 1.6x - Example feature title
Date: 2026-02-17
Designer model/session: gpt-5.3-codex, session=<fill>

## Target Bullets (excluding planning/review)
- [ ] Add idempotency enforcement for market close command. (SP=3) [REQ-12.1]
- [ ] Add integration test coverage for duplicate idempotency behaviors. (SP=1) [REQ-12.1]

## Goal
- Make close command exactly-once across retries.

## Non-goals
- No refactor of unrelated command services.

## In Scope
- Validator + service + integration tests for the close command path.

## Out of Scope
- Any API shape changes outside close command behavior.

## Things to Decide (for final planning discussion)
- Response strategy scope:
  - Option 1 (recommended): strictly reuse ADR-0001 response strategy for this endpoint.
  - Option 2: allow an endpoint-specific response variant for close-command duplicates.
- Duplicate mismatch error contract:
  - Option 1 (recommended): keep HTTP 409 with existing error code for consistency.
  - Option 2: keep HTTP 409 but introduce a narrower domain title/code for mismatch.

## Trade-offs
- Keep response minimal for stable replay; clients use query endpoint for current state.

## Proposal / Design Details
- Validate input and preconditions first.
- Append ledger event once and reject payload mismatch on duplicate key.
- Keep projection updates in same transaction.

## Risks and Mitigations
- Race between close and other state-gated commands -> enforce stream lock order used in existing services.

## Quality and Testing
- Add integration coverage for first call, duplicate same payload, duplicate mismatched payload.

## Alternatives
- Use projection-derived idempotent replay -> rejected due to instability after subsequent events.

## Applicable ADR Shortlist (from ai/decisions.md)
- ADR-0001 — idempotent duplicate response behavior is directly relevant for close retries.
- ADR-0005 — event stream routing constraints apply to any new close-command writes.

## Applicable AGENTS.md Constraints
- Command validation before writes.
- Transaction rollback on any exception.
- Stable error semantics and API doc updates if contract changes.

## Applicable User Review Rules
- UR-0021: avoid thin wrappers with no semantics.
- UR-0022: enforce state invariants at DB/authoritative boundary when applicable.

## References in Current Codebase
Optional in design phase. Required for non-trivial behavior changes; this example includes multiple references.
- `src/main/java/com/teleforecaster/cmms/service/MarketCloseService.java` - existing close flow.
- `src/main/java/com/teleforecaster/cmms/persistence/LedgerRepository.java` - append/idempotency path.
- `src/test/java/com/teleforecaster/cmms/api/MarketCloseResourceIT.java` - integration assertions pattern.

## Unknowns / Assumptions to Validate (optional)
- None.
