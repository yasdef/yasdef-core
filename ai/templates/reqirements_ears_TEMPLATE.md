# Requirements (EARS) - Template

Use this template to author requirements in a format that is easy for an AI (and humans) to follow and reproduce across projects.

System name: <System Name>  
Scope: <1–2 lines describing what this system is and is not>

---

## Overview
- Product/Domain: <brief description>
- Goals: <high-level outcomes>
- Out of scope: <explicit non-goals>

## Glossary
- <Term>: <Definition>

## Actors
- <Actor>: <Description>

## Assumptions
- <Assumption>

---

## Requirements

Author each requirement as a numbered block. Keep the structure identical for every requirement.
Use the header form `### Requirement <N> — <Short title>` (not `REQ-<N>`).

### Requirement <N> — <Short title>
**User Story:** As a <role>, I want <capability>, so that <benefit>.

**Acceptance Criteria (EARS):**
- (Choose only the relevant EARS patterns; delete the rest.)
- THE <System Name> SHALL <capability>.
- WHEN <event>, THE <System Name> SHALL <response>.
- WHILE <state>, THE <System Name> SHALL <response>.
- WHERE <feature is enabled>, THE <System Name> SHALL <response>.
- IF <undesired condition>, THEN THE <System Name> SHALL <response>.
- WHEN <event> AND WHILE <state>, THE <System Name> SHALL <response>.

**Verification:** <tests, endpoints, logs, metrics, docs that prove this requirement is met>

---

### Requirement <N+1> — <Short title>
**User Story:** As a <role>, I want <capability>, so that <benefit>.

**Acceptance Criteria (EARS):**
- <one EARS statement per bullet; keep each bullet independently testable>

**Verification:** <tests, endpoints, logs, metrics, docs that prove this requirement is met>

---

## Non-Functional Requirements

Write NFRs using the same block structure so they stay as precise and testable as functional requirements.

### NFR <N> — <Short title>
**User Story:** As a <role>, I want <quality attribute>, so that <benefit>.

**Acceptance Criteria (EARS):**
- THE <System Name> SHALL <latency/availability/security/compliance constraint>.

**Verification:** <load test, SLO dashboard, security checks, audit evidence>

---

## Authoring rules (for consistency)
- Put the EARS statements only under **Acceptance Criteria (EARS):** (avoid mixing “design notes” into criteria).
- Use exactly one EARS statement per bullet; do not join multiple behaviors with “and” unless it is a true combined EARS form.
- Prefer `SHALL` for mandatory behavior; use `MAY` only for explicitly optional behavior.
- Make criteria verifiable: include concrete triggers, states, API shapes/status codes, data fields, or measurable thresholds where applicable.
