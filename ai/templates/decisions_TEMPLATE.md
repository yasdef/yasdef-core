# Decisions (ADR-lite)

This file records architectural and API decisions that affect correctness, security, or long-term maintainability.

Rules:
- Put **decisions** here (the “why”), not in `ai/blocker_log.md`.
- Put **unknowns/blockers** in `ai/blocker_log.md` under an in-progress step in `ai/implementation_plan.md`.
- When a decision changes an API, update `src/main/resources/openapi.yaml` (and Postman when required by `AGENTS.md`).

Template:
- **ID**: ADR-XXXX
- **Status**: Proposed | Accepted | Superseded
- **Superseded by**: ADR-XXXX (optional)
- **Date**: YYYY-MM-DD
- **Context**
- **Decision**
- **Consequences**
- **Related**: requirements / plan steps / code

---

## ADR-0001 — Idempotent responses are derived from ledger data
- **Status**: Accepted
- **Date**: 2026-01-22
- **Context**: Command endpoints must be safely retryable. Retries must not double-apply state and must return a stable response representing the original outcome.
- **Decision**:
  - On duplicate `Idempotency-Key`, do not write new ledger events or projections.
  - Return the original command response derived from immutable ledger data (event metadata and/or event payload), not from projections.
  - Detect mismatched retries by comparing `payload_hash` and reject deterministically when different.
  - For redeem (and other commands with potentially large/computed outputs), keep the command response minimal and rely on query endpoints for current totals.
- **Consequences**:
  - Responses stay stable across retries even if projections have advanced.
  - Some commands may require adding response-relevant fields into the event payload (or performing a dedicated ledger payload read) to reconstruct stable responses without projections.
- **Related**: `reqirements_ears.md` (Requirement 2), `ai/implementation_plan.md` (Step 1.2).

## ADR-0002 — Ledger append API returns a minimal result
- **Status**: Accepted
- **Date**: 2026-01-22
- **Context**: Many commands need to know whether an append was new vs duplicate to avoid double-applying projections. Returning full payloads on every append increases coupling and can be expensive.
- **Decision**:
  - `LedgerRepository.appendEvent(...)` returns a minimal `LedgerAppendResult` including `inserted`, `streamId`, `streamType`, `eventType`, `payloadHash`, and `eventHash`.
  - Stable idempotent responses should use event metadata where possible; if payload is needed, add an explicit repository read for it (do not bloat the append result).
- **Consequences**:
  - Non-create commands (publish/close/resolve/redeem) can reliably detect duplicates via `inserted`.
  - If future responses require payload fields, an explicit read-path will be introduced.
- **Related**: `src/main/java/com/teleforecaster/cmms/persistence/LedgerRepository.java`, `src/main/java/com/teleforecaster/cmms/domain/LedgerAppendResult.java`.

## ADR-0003 — Testcontainers-based codegen/test gate
- **Status**: Superseded
- **Superseded by**: ADR-0004
- **Date**: 2026-01-22
- **Context**: Developers need a single verification command that runs Liquibase migrations, jOOQ codegen, and tests without relying on a pre-provisioned local database.
- **Decision**:
  - Initial approach used `jdbc:tc` URLs for Liquibase and jOOQ codegen.
- **Consequences**:
  - Required Testcontainers reuse configuration and plugin classpath fixes.
- **Related**: `pom.xml`, `AGENTS.md`, `ai/AI_DEVELOPMENT_PROCESS.md`.

## ADR-0004 — Orchestrated Testcontainers codegen/test gate
- **Status**: Accepted
- **Date**: 2026-01-24
- **Context**: `jdbc:tc` in multiple Maven plugins created container reuse and classpath issues during code generation.
- **Decision**:
  - Use a single Testcontainers Postgres instance started in the build via `gmavenplus-plugin`.
  - Export JDBC URL and credentials to Maven properties for Liquibase and jOOQ to consume.
  - Use `./mvnw -Ptc-codegen test` as the default end-to-end verification gate.
- **Consequences**:
  - Liquibase and jOOQ always target the same database instance within a single Maven run.
  - No dependency on Testcontainers JDBC reuse configuration.
- **Related**: `pom.xml`, `AGENTS.md`, `ai/AI_DEVELOPMENT_PROCESS.md`.

## ADR-0005 — Stream routing strategy for ledger events
- **Status**: Accepted
- **Date**: 2026-01-24
- **Context**: Ledger events are hash-chained per stream. A consistent stream routing rule is needed so future commands append to the correct stream and preserve auditability.
- **Decision**:
  - Market lifecycle events append to the market stream (`stream_type=MARKET`, `stream_id=marketId`).
  - Balance/position events append to the user stream (`stream_type=USER`, `stream_id=userId`).
  - Trade/redemption events may append to both market and user streams for tamper-evident trails.
- **Consequences**:
  - Implementations must follow the routing rule when new commands are added.
  - No code-level enforcement is introduced yet; the rule is applied during command implementation.
- **Related**: `ai/implementation_plan.md` (Step 1.2).

## ADR-0022 — CPMM outcome-share AMM (Phase 1+2) with LP-only fees
- **Status**: Accepted
- **Date**: 2026-02-07
- **Context**: The initial CMMS MVP implemented pooled staking (YES/NO stake accumulation) plus a worker-driven payout sweep. The product direction requires a single approach that can support Phase 1 (OFF_CHAIN points) and Phase 2 (TON) without a fundamental redesign, and aims to avoid “house as counterparty” mechanics by using market-style trading.
- **Decision**:
  - Use a binary (YES/NO) AMM based on a constant-product market maker (CPMM) with “complete set” semantics:
    - Collateral can be split into 1 YES share + 1 NO share.
    - Settlement redeems YES (or NO) shares for collateral based on the resolved outcome.
  - Liquidity is provided by external LPs/market makers; the platform does not seed liquidity.
  - Fee model: platform fee is 0; a configurable LP fee is charged on swaps and retained by the pool (LP-only fees).
  - LP lifecycle defaults:
  - LPs can add liquidity only while the market is in a dedicated LP-only `PUBLISHED` state (not visible to regular users).
    - LPs can withdraw liquidity only after the market is `RESOLVED`.
  - Market can transition from `PUBLISHED` to `OPEN` only after meeting a configurable minimum initial liquidity threshold (`cmms.amm.min-initial-liquidity`, default 100 points for Phase 1).
  - Initial price is chosen by LPs via the initial YES/NO reserve ratio, but is bounded by configuration:
    - Define `pYes = R_no / (R_yes + R_no)` for initial implied probability.
    - Enforce `pYes ∈ [1 - maxInitialPrice, maxInitialPrice]` with `maxInitialPrice` defaulting to 0.9 (i.e., max 90/10 skew).
    - Recommended config representation: `cmms.amm.initial-price.max-bps = 9000` (env var `CMMS_AMM_INITIAL_PRICE_MAX_BPS`), with the minimum derived as `10000 - max`.
    - Enforce a minimum per-side reserve at open: `min_side_reserve = max(1, cmms.amm.min-initial-liquidity / 10)`.
  - Phase 2 custody model: CMMS does not custody TON. Trading/settlement is on-chain; CMMS acts as an internal system of record for market definitions, resolution, and off-chain indexing/reporting.
  - Trade API semantics: use “exact input” (buy/sell specify input amount and a slippage-protecting minimum output).
  - Accounting representation: integer-only quantities (points in Phase 1; nanoTON and integer outcome shares in Phase 2).
  - Phase 1 collateral handling: use a per-market escrow/projection model (do not reuse global `balances_projection.locked_balance` as the primary AMM escrow once buy/sell is supported).
  - Settlement mechanics: MVP uses explicit user-driven redeem after `RESOLVED`; a worker-driven auto-redeem sweep may be added later as technical debt.
  - Disputes interaction: if a market transitions `RESOLVED → DISPUTED → RESOLVED`, freeze redemptions while `DISPUTED` and only allow redemption after final resolution.
- **Consequences**:
  - This supersedes “stake pooling” semantics for user participation; CMMS will need new endpoints, ledger events, and projections for trades, pool state, and share balances.
  - The existing Step 1.6 “payout” concept becomes “settlement/redemption” in the AMM model rather than a single payout sweep of stakes.
- **Related**: `reqirements_ears.md` (REQ-9, REQ-12), `ai/implementation_plan.md` (Step 1.6 and earlier forecast mechanics).

## ADR-0024 — LP share minting and funding accounting (Phase 1)
- **Status**: Accepted
- **Date**: 2026-02-07
- **Context**: Step 1.6a introduces LP funding with a new AMM pool projection and per-market escrow. We need a deterministic LP share minting rule and a clear accounting path for OFF_CHAIN liquidity adds that aligns with mode isolation and existing balances.
- **Decision**:
  - LP share minting uses a simple collateral-sum rule: `lpSharesMinted = yesAmount + noAmount`.
  - Pool totals track collateral units: `lp_total_shares` is incremented by `yesAmount + noAmount`, and remains aligned with `yes_reserve + no_reserve` when funding adds are proportional.
  - OFF_CHAIN liquidity adds reduce `balances_projection.available_balance` by `yesAmount + noAmount`. LP collateral is tracked in `market_escrow_projection`; `balances_projection.locked_balance` remains reserved for legacy stake locking.
- **Consequences**:
  - LP share minting is deterministic and integer-only (no fractional shares).
  - Future withdrawals/redemptions must use `market_escrow_projection` and LP shares rather than `balances_projection.locked_balance`.
- **Related**: `ai/implementation_plan.md` (Step 1.6a), `src/main/java/com/teleforecaster/cmms/service/LiquidityProvisionService.java`.

## ADR-0025 — Step 1.6b: Trade math, rounding, and positions projection (Phase 1)
- **Status**: Accepted
- **Date**: 2026-02-07
- **Context**: Public buy/sell trading (REQ-9) requires deterministic integer CPMM math and a clear per-user outcome share position projection. Step 1.6b replaces stake-based forecasting with CPMM trades, so the system must define canonical formulas and rounding rules that are stable under retries and safe under concurrency.
- **Decision**:
  - Use binary complete-set / FPMM-style integer trade formulas:
    - **Buy (exact collateral in)** uses `ceilDiv` on the updated reserve to ensure rounding is against the trader.
    - **Sell (exact shares in)** solves the quadratic for collateral out using a deterministic integer `floorSqrt`, and floors the final division to ensure rounding is against the trader.
  - Use `BigInteger` for intermediate calculations (products/squares) to avoid `long` overflow.
  - Append each trade command as a single ledger event to the market stream (`stream_type=MARKET`, `stream_id=marketId`) and include `userId` in the event payload.
  - Add a dedicated `outcome_share_positions_projection` table with `(market_id, user_id)` primary key and `yes_shares/no_shares` columns; do not repurpose the legacy `positions_projection.yes_total_stake/no_total_stake` columns for shares.
  - Defer LP fee mechanics for Step 1.6b; treat LP fee as `0` for initial public trading and implement fees in a follow-up step.
- **Consequences**:
  - Trade execution is deterministic and integer-only with rounding that does not overpay the trader.
  - Stake-based projections remain as legacy state until the forecast endpoint is removed and the schema is cleaned up in a later step.
- **Related**: `reqirements_ears.md` (Requirement 9), `ai/implementation_plan.md` (Step 1.6b).

## ADR-0026 — Step 1.6c: Redeem-all endpoint and redeemed position markers
- **Status**: Accepted
- **Date**: 2026-02-09
- **Context**: Step 1.6c adds public redemption (REQ-12). We want a projection-level marker that a user has redeemed (to make the remaining losing-side shares clearly “post-settlement”), without destroying losing-side share counts.
- **Decision**:
  - `POST /v1/markets/{marketId}/redeem` is **redeem-all only** (no request body); it redeems the caller’s full winning-share balance for the resolved outcome.
  - Add nullable columns to `outcome_share_positions_projection`:
    - `redeemed_at TIMESTAMPTZ`
    - `redeemed_outcome TEXT` with values `{YES, NO}`
  - On successful redemption, decrement only the winning-side shares and set `redeemed_at/redeemed_outcome` on the row; do not zero losing-side shares.
  - Redemption is allowed whenever a market is `RESOLVED`; redemptions are frozen only while `DISPUTED` (no clawback/retroactive adjustment is designed yet if outcome later changes).
- **Consequences**:
  - Clients can treat the position as “settled” based on `redeemed_at` while still showing losing-side shares as a historical/diagnostic remainder.
  - If the market later transitions `RESOLVED → DISPUTED → RESOLVED` with a different outcome, clawback/adjustment semantics are not defined yet; a dedicated dispute/redemption consistency design is required as future work.
- **Related**: `reqirements_ears.md` (Requirement 12, Requirement 2), `ai/implementation_plan.md` (Step 1.6c).

## ADR-0006 — Centralized error response format and mappings
- **Status**: Superseded
- **Superseded by**: ADR-0007
- **Date**: 2026-01-24
- **Context**: The API must return stable error codes and consistent JSON error bodies for clients and retries.
- **Decision**:
  - Use a simple JSON error shape: `{ "code": "...", "message": "...", "details": { ... } }`, where `details` is optional.
  - Map validation errors (`ConstraintViolationException`, `IllegalStateException` used for validation) to `VALIDATION_FAILED` (HTTP 400).
  - Map idempotency mismatches to `DUPLICATE_IDEMPOTENCY_KEY` (HTTP 409).
  - Map invalid transitions to `INVALID_TRANSITION` (HTTP 409).
  - Map not-found cases to `NOT_FOUND` (HTTP 404).
  - Map internal failures to `INTERNAL_ERROR` (HTTP 500) with a generic message.
- **Consequences**:
  - Service code should reserve `IllegalStateException` for validation/matching errors; internal failures use dedicated exceptions.
  - API tests should assert error `code` values for failure cases.
- **Related**: `reqirements_ears.md` (error codes), `src/main/resources/openapi.yaml`.

## ADR-0007 — Quarkus default error format with stable titles
- **Status**: Superseded
- **Superseded by**: ADR-0008
- **Date**: 2026-01-25
- **Context**: Simplify error handling while keeping stable error codes, and align with Quarkus’ default validation response shape.
- **Decision**:
  - Use Quarkus’ default validation error JSON shape (`title`, `status`, `violations`) for all error responses.
  - Map error codes to the `title` field (e.g., `VALIDATION_FAILED`, `INVALID_TRANSITION`).
  - Validation and JSON parsing errors return HTTP 400 with `title=VALIDATION_FAILED` and `violations` entries.
- **Consequences**:
  - API responses no longer return `code/message/details`.
  - Clients should rely on `title` for stable error codes.
- **Related**: `reqirements_ears.md` (error codes), `src/main/resources/openapi.yaml`, `src/main/java/com/teleforecaster/cmms/api/error/`.

## ADR-0008 — Use Quarkus defaults for validation and JSON parsing errors
- **Status**: Accepted
- **Date**: 2026-01-25
- **Context**: Prefer Quarkus default error responses for validation and JSON parsing while keeping stable titles for domain errors.
- **Decision**:
  - Keep Quarkus’ built-in validation response for bean validation failures (`title=Constraint Violation`, `status`, `violations`).
  - Keep Quarkus’ built-in JSON parsing error response for malformed payloads (e.g., invalid enum values).
  - Continue mapping domain/runtime errors to `ViolationReport` with stable titles (e.g., `DUPLICATE_IDEMPOTENCY_KEY`).
- **Consequences**:
  - Validation errors no longer return `VALIDATION_FAILED` as a title.
  - Clients must tolerate Quarkus’ default JSON parse error shape in 400s.
- **Related**: `reqirements_ears.md` (error codes), `src/main/resources/openapi.yaml`, `src/main/java/com/teleforecaster/cmms/api/error/ErrorExceptionMapper.java`.

## ADR-0009 — Balance initialization endpoint and insufficient balance semantics
- **Status**: Accepted
- **Date**: 2026-01-27
- **Context**: Public trading needs a deterministic way to initialize user balances and return stable error codes for balance-related failures.
- **Decision**:
  - Add `POST /internal/v1/users/{userId}/balance` with required `Idempotency-Key` and optional `initialBalance` in the request body.
  - Response body returns metadata only (`userId`, `status=CREATED`) and always responds with HTTP 201; it does not return current balances.
  - Treat missing `balances_projection` rows as `NOT_FOUND`.
  - Return `INSUFFICIENT_BALANCE` with HTTP 409 when available balance is insufficient for a trade.
- **Consequences**:
  - Public trading assumes a pre-existing balance row; onboarding must call the internal endpoint.
  - Clients can distinguish missing-user balance from insufficient funds via error codes and status.
- **Related**: `ai/implementation_plan.md` (Step 1.3a), `reqirements_ears.md` (Requirements 9, 18).

## ADR-0010 — Publish endpoint response shape
- **Status**: Accepted
- **Date**: 2026-01-28
- **Context**: Publish transitions can be followed by other state changes immediately, so returning the current market state is not reliably idempotent.
- **Decision**:
  - `POST /internal/v1/markets/{marketId}/publish` returns HTTP 200 with body `{ "marketId": "..." }` only.
  - Idempotent replays return the same response shape.
- **Consequences**:
  - Clients must query market state separately after publish if they need it.
- **Related**: `ai/implementation_plan.md` (Step 1.4), `reqirements_ears.md` (Requirement 6).

## ADR-0011 — Automatic close scheduling and idempotency keys
- **Status**: Accepted
- **Date**: 2026-01-29
- **Context**: Automatic market close must run at or after `close_time` and remain idempotent across retries or scheduler restarts.
- **Decision**:
  - Use Quarkus scheduler to poll for OPEN markets with `close_time <= now` on a configurable interval (`cmms.market.close.scheduler.every`, default `1m`).
  - Generate deterministic auto-close idempotency keys with the prefix `auto-close:` plus `marketId`.
- **Consequences**:
  - Auto-close latency is bounded by the scheduler interval and is configurable per environment.
  - Repeated scheduler runs safely re-use the same idempotency key without double-applying events.
- **Related**: `ai/implementation_plan.md` (Step 1.4a), `reqirements_ears.md` (Requirement 7).

## ADR-0012 — Resolve request fields and server-generated resolvedAt
- **Status**: Superseded
- **Superseded by**: ADR-0013
- **Date**: 2026-01-29
- **Context**: Resolve must capture outcome, resolver metadata, and evidence references while keeping idempotency safe and audit fields consistent.
- **Decision**:
  - `POST /internal/v1/markets/{marketId}/resolve` accepts `outcome` (YES/NO), `resolvedBy` (string), and optional `evidenceRefs` (array of strings).
  - `resolvedAt` is generated server-side at command execution and stored in the `MarketResolved` ledger payload.
  - Idempotent retries validate against the persisted payload when resolving `resolvedAt`.
- **Consequences**:
  - Clients do not supply `resolvedAt`; it reflects the server’s resolution time.
  - Retry validation requires loading the ledger payload for the idempotency key.
- **Related**: `ai/implementation_plan.md` (Step 1.5), `reqirements_ears.md` (Requirement 8).

## ADR-0013 — Resolve payload hash excludes server-generated resolvedAt
- **Status**: Accepted
- **Date**: 2026-01-29
- **Context**: Idempotent retries for resolve should avoid extra ledger payload reads while still validating client-supplied inputs.
- **Decision**:
  - Keep `resolvedAt` server-generated and stored in the ledger payload.
  - Exclude `resolvedAt` from the canonical payload hash for resolve commands.
  - Idempotent retry validation compares the hash derived from `marketId`, `outcome`, `resolvedBy`, and `evidenceRefs` only.
- **Consequences**:
  - Resolve no longer needs an extra payload read on retries.
  - Idempotency validation still rejects mismatched client inputs, while tolerating the server-generated timestamp.
- **Related**: `ai/implementation_plan.md` (Step 1.5), `reqirements_ears.md` (Requirement 8).

## ADR-0014 — Dispute escalation is always permitted; resolve projections include core fields
- **Status**: Accepted
- **Date**: 2026-02-02
- **Context**: Step 1.5a requires implementing the DISPUTED transition and resolved projections. The dispute escalation trigger source and projection fields needed a decision to proceed.
- **Decision**:
  - Treat dispute escalation as always eligible; no global or per-market configuration is required to allow CLOSED → DISPUTED.
  - Project resolved outcome fields into the market read model: `outcome`, `resolvedBy`, and `resolvedAt`.
- **Consequences**:
  - Resolve flow can always transition to DISPUTED when escalation is required.
  - Market projections must add resolved fields; evidence refs storage is handled separately.
- **Related**: `ai/implementation_plan.md` (Step 1.5a), `reqirements_ears.md` (Requirement 8).

## ADR-0015 — Market state evidence stored in a join table
- **Status**: Accepted
- **Date**: 2026-02-02
- **Context**: Resolved and disputed states need evidence references stored in projections. Existing migrations use JSONB for disputes, but the repository guidelines prefer join tables over JSONB for collections.
- **Decision**:
  - Store evidence references for market state transitions in a dedicated join table keyed by `market_id` and `state` (RESOLVED/DISPUTED).
  - Use the same table for resolved and disputed evidence to keep projection handling consistent.
- **Consequences**:
  - A new join table is added with a composite key to prevent duplicate evidence refs.
  - Projection updates will insert evidence refs into the join table instead of JSONB.
- **Related**: `ai/implementation_plan.md` (Step 1.5a), `reqirements_ears.md` (Requirement 8).

## ADR-0016 — Resolve request supports explicit dispute escalation
- **Status**: Accepted
- **Date**: 2026-02-02
- **Context**: Step 1.5a requires a trigger for CLOSED → DISPUTED from resolve. We needed a deterministic API input to choose escalation behavior.
- **Decision**:
  - Add optional boolean `escalate` to `MarketResolveRequest`.
  - When `escalate=true`, the resolve endpoint transitions the market to DISPUTED and appends a `MarketDisputeEscalated` ledger event instead of resolving.
- **Consequences**:
  - Resolve requests now have two paths; clients can explicitly request escalation.
  - Payload hash includes the `escalate` flag to keep idempotency strict.
- **Related**: `src/main/resources/openapi.yaml`, `ai/implementation_plan.md` (Step 1.5a), `reqirements_ears.md` (Requirement 8).

## ADR-0017 — Allow open resolution proposals via resolution criteria code
- **Status**: Superseded
- **Superseded by**: ADR-0018
- **Date**: 2026-02-02
- **Context**: Resolution proposals should be allowed while a market is OPEN only for certain markets, while others should accept proposals after CLOSE. A simple per-market rule is needed without introducing new schema fields.
- **Decision**:
  - Use a resolution criteria code flag to allow proposals in the OPEN state.
  - Markets with the resolution criteria code `ALLOW_OPEN_PROPOSALS` may accept proposals in OPEN, CLOSED, or DISPUTED states.
  - Markets without the criteria code may accept proposals only in CLOSED or DISPUTED states (RESOLVED is always rejected).
- **Consequences**:
  - The criteria code must exist in `resolution_criteria` and be linked to the market via `market_resolution_criteria`.
  - The proposal endpoint performs a criteria lookup before accepting OPEN-state submissions.
- **Related**: `reqirements_ears.md` (Requirement 11), `ai/implementation_plan.md` (Step 1.5b).

## ADR-0018 — Allow open resolution proposals via market flag
- **Status**: Accepted
- **Date**: 2026-02-03
- **Context**: The OPEN proposal rule is a policy flag, not a resolution criterion. It should be configured per market without polluting resolution criteria.
- **Decision**:
  - Add `allow_open_proposals` to `markets_projection` with default `false`.
  - Expose `allowOpenProposals` in `MarketDraftRequest` to set it at draft creation.
  - If `allowOpenProposals=true`, proposals are accepted in OPEN, CLOSED, or DISPUTED; otherwise only CLOSED or DISPUTED (RESOLVED always rejected).
- **Consequences**:
  - Market draft creation now includes a policy flag to gate proposal timing.
  - Proposal validation uses the market flag instead of resolution criteria codes.
- **Related**: `reqirements_ears.md` (Requirement 11), `ai/implementation_plan.md` (Step 1.5b).

## ADR-0019 — Resolution proposals projection with confidence-only escalation flag
- **Status**: Accepted
- **Date**: 2026-02-03
- **Context**: Resolution proposals need to be queryable for admin review. The initial escalation workflow is not implemented, so escalation should be a simple flag for now.
- **Decision**:
  - Persist each accepted proposal in `resolution_proposals_projection` with sources in `resolution_proposal_sources`.
  - Store `escalated=true` when `confidence < 0.5`; no separate escalation ledger event for now.
- **Consequences**:
  - Admin/worker tooling can query proposals via projections.
  - Escalation remains advisory until a downstream workflow is added.
- **Related**: `reqirements_ears.md` (Requirement 11), `ai/implementation_plan.md` (Step 1.5b).

## ADR-0020 — Resolution source upsert idempotency and conflict handling
- **Status**: Accepted
- **Date**: 2026-02-04
- **Context**: Step 1.5c introduces an internal resolution source upsert endpoint. We need deterministic idempotency handling without ledger events and explicit behavior when a source code already exists.
- **Decision**:
  - Implement `POST /internal/v1/resolution-sources` as a database-only upsert (no ledger event).
  - Do not add a dedicated idempotency table; retries rely on the existing source row only.
  - Reject any request that targets an existing `source_code` with a validation error (HTTP 400), regardless of label.
  - Return HTTP 201 only when a new source is created.
- **Consequences**:
  - Idempotency mismatches are not detected; duplicates always return HTTP 400.
  - Source label changes require a separate endpoint or migration rather than implicit updates.
- **Related**: `ai/implementation_plan.md` (Step 1.5c).

## ADR-0021 — Resolution proposal query response shape and missing-market handling
- **Status**: Accepted
- **Date**: 2026-02-04
- **Context**: Step 1.5d adds an internal query for resolution proposals. We needed to decide the response shape, ordering, pagination, and missing-market behavior.
- **Decision**:
  - `GET /internal/v1/markets/{marketId}/resolution-proposals` returns a response containing `marketId` and an ordered list of proposals with `proposalId`, `outcome`, `evidenceBundleRef`, `confidence`, `escalated`, `createdAt`, and `sources` (code + label).
  - Order proposals by `createdAt` desc, then `proposalId` desc; order sources by `sourceCode` asc.
  - No pagination parameters for now.
  - Return HTTP 404 when the market does not exist.
- **Consequences**:
  - Clients can render proposal history deterministically but must query again if paging is needed later.
  - Future pagination would require an additive API change.
- **Related**: `ai/implementation_plan.md` (Step 1.5d), `src/main/resources/openapi.yaml`.

## ADR-0023 — Step 1.6a: TON-mode rejection and proportional liquidity adds
- **Status**: Accepted
- **Date**: 2026-02-07
- **Context**: Step 1.6a introduces LP funding and an open gate. Requirement 15 requires strict accounting-mode isolation (OFF_CHAIN vs TON), and funding behavior must avoid price manipulation during the PUBLISHED phase.
- **Decision**:
  - For Step 1.6a (Phase 1 / off-chain), deterministically reject LP funding and market open operations for `TON`-mode markets; TON-mode funding/open will be implemented in Phase 2 with dedicated TON accounting paths.
  - After the first liquidity deposit initializes a pool, any subsequent liquidity add during `PUBLISHED` must be proportional to the current pool reserves (i.e., it must not change the pool price).
- **Consequences**:
  - Mode isolation is enforced by construction: off-chain projections (balances, pool reserves, escrow, LP positions) will not be updated for TON markets in Phase 1 flows.
  - PUBLISHED-phase liquidity adds cannot re-price the market; the initial deposit sets the starting price, and later deposits only scale liquidity.
- **Related**: `reqirements_ears.md` (Requirement 6, Requirement 15), `ai/implementation_plan.md` (Step 1.6a).

## ADR-0027 — Market-stream lock-first ordering for state-gated market commands
- **Status**: Accepted
- **Date**: 2026-02-10
- **Context**: State-gated commands on market streams could read/validate `markets_projection.state` and lock projection rows before acquiring the market stream ledger head lock. Under concurrency (for example trade vs close), this allowed stale-state validation and inconsistent lock ordering that increased deadlock risk.
- **Decision**:
  - For all MARKET-stream commands that depend on market state (trade, publish, open, close, resolve/dispute, redeem, resolution proposal submit), acquire `ledger_heads` lock (`stream_type=MARKET`, `stream_id=marketId`, `FOR UPDATE`) immediately after idempotency fast-path and before state-dependent reads/validation.
  - Standardize command lock ordering as: market stream head lock -> projection locks -> ledger append -> projection writes.
  - Keep `appendEvent(...)` behavior unchanged; re-locking the same stream head row in the same transaction is allowed and preserves existing append semantics.
- **Consequences**:
  - Market command linearization happens before state validation, closing stale-read races.
  - Projection lock acquisition order is consistent with stream lock ordering, reducing deadlock risk.
  - Per-market contention can increase slightly due to earlier serialization, which is accepted for correctness.
- **Related**: `reqirements_ears.md` (Requirement 3, Requirement 4, Requirement 9), `ai/implementation_plan.md` (Step 1.6d).
