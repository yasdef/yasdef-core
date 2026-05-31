# AI audit result - golden example

## Summary
- Step: `1.6`
- Feature: `trade-concurrency-1777635876`
- Branch / commit: `step-1.6-trade-concurrency-1777635876-review`, `abc1234`
- Scope reviewed: market-close/trade concurrency behavior and step target-bullet proof

## Discovery Notes
- Discovery completed in one pass before disposition.
- Findings source constraints respected (target bullet proof, scope drift, AGENTS invariant, TODO markers).

## Findings

### F-01
- Severity: `Critical`
- Recommendation: `FollowupStep`
- Category: `TargetBulletNotProven`
- Target bullet / invariant: `Prevent post-close trade execution under concurrent close.`
- Reasoning: the close-state check runs before stream lock acquisition, so a concurrent close can interleave between check and append.
- References:
  - `src/main/java/com/acme/trade/TradeService.java:71 (executeTrade)`
  - `src/main/java/com/acme/trade/TradeService.java:93 (appendTradeEvent)`
  - `src/main/java/com/acme/ledger/LedgerRepository.java:35 (appendEventWithLock)`
- Disposition state:
  - [x] follow_up_created: `1.6a`
  - [ ] raised_to_coordinator:
  - [ ] rejected:

### F-02
- Severity: `Medium`
- Recommendation: `RiseToCoordinator`
- Category: `ScopeDrift`
- Target bullet / invariant: `Out-of-scope telemetry aggregation touched in this patch.`
- Reasoning: patch introduces dashboard materialization logic not listed in Goal/In Scope and contradicts Out of Scope.
- References:
  - `src/main/java/com/acme/telemetry/DashboardProjection.java:18 (rebuild)`
- Disposition state:
  - [ ] follow_up_created:
  - [x] raised_to_coordinator: `projects/trading/trade-concurrency-1777635876/raised_questions/1.6-worker-42-F02.md`
  - [ ] rejected:

### F-03
- Severity: `Low`
- Recommendation: `FollowupStep`
- Category: `TodoMarker`
- Target bullet / invariant: `//TODO marker remains in changed production path`
- Reasoning: TODO indicates unresolved behavior in a changed file; must be dispositioned.
- References:
  - `src/main/java/com/acme/trade/TradeResource.java:44 (//TODO map domain error code)`
- Disposition state:
  - [ ] follow_up_created:
  - [ ] raised_to_coordinator:
  - [x] rejected: false positive for this step; marker belongs to unrelated migration tracked separately
