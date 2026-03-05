# Implementation Plan - Golden Example

This example shows a step-only plan with balanced sizing, distinct bullets, and correct ordering.

### Step 1.1 Projection schema for orders [REQ-6] [REQ-7]
Est. step total: 13 SP
- [ ] Plan and discuss the step (SP=1)
- [ ] Define projections schema + constraints in Liquibase (SP=5)
- [ ] Add jOOQ mappings + repository read/write methods (SP=3)
- [ ] Add projection rebuild path and tests (SP=3)
- [ ] Review step implementation (SP=1)

### Step 1.2 Order creation command (write path) [REQ-4] [REQ-7]
Est. step total: 16 SP
- [ ] Plan and discuss the step (SP=1)
- [ ] Add command validator + error codes for create order (SP=3)
- [ ] Implement command handler with ledger append + projection update (SP=5)
- [ ] Add idempotency tests + failure modes (SP=5)
- [ ] Review step implementation (SP=2)

### Step 1.3 Order query endpoint (read path) [REQ-6]
Est. step total: 12 SP
- [ ] Plan and discuss the step (SP=1)
- [ ] Add query repository criteria and projection read (SP=3)
- [ ] Implement API endpoint + request/response DTOs (SP=5)
- [ ] Add query tests + update docs (SP=3)
- [ ] Review step implementation (SP=1)
