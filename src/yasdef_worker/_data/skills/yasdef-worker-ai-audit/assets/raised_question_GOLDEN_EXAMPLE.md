# Raised Question - Golden Example

## Header
- Step: `1.6`
- Feature id: `trade-concurrency-1777635876`
- Worker id: `worker-42`
- Finding id: `F-02`
- Source review artifact: `.asdlc_worker/step_review_results/review_result-1.6-trade-concurrency-1777635876.md`
- Date: `2026-05-30`

## Why raised to coordinator
- The finding requires an architectural decision across two services and has more than one viable implementation path.

## Problem statement
- Current patch introduces telemetry aggregation logic in the trade service boundary, but ownership between trade-service and analytics-service is undefined. Both paths are technically feasible and have different latency/consistency trade-offs.

## Evidence
- `src/main/java/com/acme/telemetry/DashboardProjection.java:18 (rebuild)`
- `src/main/java/com/acme/trade/TradeService.java:112 (emitTelemetrySnapshot)`

## Candidate options
- Option 1: keep aggregation in trade-service and publish normalized snapshots
  - Trade-offs: fastest delivery; increases coupling and service responsibility.
- Option 2: move aggregation to analytics-service via event subscription
  - Trade-offs: cleaner ownership; additional delivery delay and backfill work.

## Requested decision
- Confirm ownership boundary for telemetry aggregation and approve one option as the standard path for this feature line.

## Impact if delayed
- Follow-up implementation step cannot be reliably scoped; risk of rework in both services.
