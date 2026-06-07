## Review Brief (Golden Example)

- What changed: Implemented account management flow with CRUD API endpoints, service-layer rule enforcement, and repository persistence wiring.
- Start review: Begin at `AccountController` (request/response + validation), then `AccountService` (rules + transaction boundaries), then `AccountRepository` (query/mapping correctness).
- Check first: Authorization boundaries, transaction/invariant safety, and correctness of user-to-account relationship integrity.
