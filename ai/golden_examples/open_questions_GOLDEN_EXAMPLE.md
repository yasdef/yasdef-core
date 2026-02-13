# Open Questions - Golden Example

This file demonstrates the preferred structure for entries in `ai/open_questions.md`.

## Step 1.11 Security
- Which JWT verification method should be used (HS256 shared secret vs RS256/JWKS), and what issuer/audience values should be enforced?
- Which JWT claims carry user identity and banned status (claim names + expected types)?
- What 401 response shape/title should be used for auth failures (default Quarkus vs `UNAUTHORIZED` in `ErrorCode`)?

## Step 1.6d Market-stream locking for state-gated commands (stream-lock-first)
- No open questions.
