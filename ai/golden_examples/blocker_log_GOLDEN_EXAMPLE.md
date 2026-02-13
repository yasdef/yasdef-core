# Blocker Log - Golden Example

This file demonstrates the preferred structure for entries in `ai/blocker_log.md`.

Rules:
- Only record true blockers for in-progress steps.
- Keep entries concise and actionable.

Template:
## Step <step> <step title>
- No blockers identified.
- Blocker: <short description>
  - Impact: <why it blocks progress>
  - Needed: <decision, info, or action required>
  - Status: Open | Resolved

---

## Step 1.6b CPMM AMM trading (public buy/sell)
- Blocker: Fee rounding policy not defined.
  - Impact: Trade math depends on deterministic rounding rules; cannot finalize formulas.
  - Needed: Decision on rounding direction and acceptable precision.
  - Status: Open

## Step 1.6c Redemption after resolution (public redeem)
- No blockers identified.
