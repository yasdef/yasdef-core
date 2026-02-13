# Decisions (ADR-lite) - Golden Example

This file demonstrates the preferred structure for entries in `ai/decisions.md`.

Rules:
- Keep the decision concise and focused on the "why".
- Link to requirements, plan steps, or code when applicable.

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

## ADR-9999 — Example decision title
- **Status**: Accepted
- **Date**: 2026-02-11
- **Context**: Briefly describe the problem and why a decision is needed.
- **Decision**:
  - State the chosen approach.
  - Include key rules or constraints.
- **Consequences**:
  - Note the impact on behavior, risk, or maintenance.
- **Related**: `reqirements_ears.md` (REQ-XX), `ai/implementation_plan.md` (Step X.Y), `src/main/java/...`
